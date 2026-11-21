import { prisma } from './prisma';
import { getSettings } from './settings';
import { distanceMeters } from '../utils/geo';
import { notifyCommuter } from '../utils/notify';
import type { GpsReading } from './boarding';

/**
 * Presence check AFTER boarding. Boarding is confirmed from a few GPS readings
 * taken while the commuter is beside the jeepney — but standing at the curb as
 * a jeepney stops or passes looks identical, and nothing used to look again, so
 * someone who never got on stayed counted as a passenger until the trip ended.
 *
 * While the commuter's app is open on the "on board" screen it sends a reading
 * every few seconds. A passenger is released (closed as CANCELLED, so the count
 * and the seat come back) only on POSITIVE evidence of separation: several
 * consecutive usable readings, over a minimum time, all well beyond the
 * boarding distance from a FRESH jeepney position.
 *
 * Deliberately conservative — a real rider must never be dropped:
 *  - silence (app closed, phone dead, no signal) never releases anyone;
 *  - stale / inaccurate readings, or a stale jeepney position, are ignored
 *    (they neither count toward release nor reset it);
 *  - one reading near the jeepney resets the run;
 *  - the release distance is far larger than the boarding distance, to absorb
 *    GPS error and the few seconds the jeepney's last ping can lag behind.
 */

/** Jeepney moves ~11 m/s; keep its position this fresh so lag stays small. */
const DRIVER_MAX_AGE_SECONDS = 20;

export type PresenceResult =
  | { status: 'NOT_BOARDED' }
  | { status: 'ON_BOARD'; away: number; required: number; verified?: boolean }
  | { status: 'RELEASED'; tripId: string; boardingId: string };

export async function submitPresenceReading(commuterId: string, reading: GpsReading): Promise<PresenceResult> {
  const settings = await getSettings();
  const boarding = await prisma.tripBoarding.findFirst({
    where: { commuterId, alightedAt: null, status: 'BOARDED' },
    orderBy: { boardedAt: 'desc' },
  });
  if (!boarding) return { status: 'NOT_BOARDED' };
  // Already seen travelling with the jeepney — nothing left to check.
  if (boarding.ridingVerifiedAt) {
    return { status: 'ON_BOARD', away: 0, required: settings.presenceReleaseReadings as number, verified: true };
  }
  const trip = await prisma.trip.findUnique({
    where: { id: boarding.tripId },
    select: { status: true, currentLat: true, currentLng: true, locationUpdatedAt: true },
  });
  if (!trip || trip.status !== 'ACTIVE') return { status: 'NOT_BOARDED' };

  const now = new Date();
  const required = settings.presenceReleaseReadings as number;

  const usable =
    reading.fixAgeSeconds !== undefined &&
    reading.fixAgeSeconds <= (settings.boardingMaxFixAgeSeconds as number) &&
    reading.accuracy !== undefined &&
    reading.accuracy <= (settings.boardingMaxAccuracyMeters as number) &&
    trip.currentLat !== null &&
    trip.currentLng !== null &&
    trip.locationUpdatedAt !== null &&
    now.getTime() - trip.locationUpdatedAt.getTime() <= DRIVER_MAX_AGE_SECONDS * 1000;

  if (!usable) return { status: 'ON_BOARD', away: boarding.awayReadings, required };

  const distance = distanceMeters(reading.lat, reading.lng, trip.currentLat!, trip.currentLng!);
  const limit = (settings.presenceReleaseDistanceMeters as number) + reading.accuracy!;

  // Movement matching: how far each phone has travelled since boarding.
  const moveNeeded = settings.presenceVerifyMoveMeters as number;
  let jeepMoved = 0;
  let commuterMoved = 0;
  if (boarding.jeepLatAtBoard !== null && boarding.jeepLngAtBoard !== null && boarding.boardedLat !== null && boarding.boardedLng !== null) {
    jeepMoved = distanceMeters(trip.currentLat!, trip.currentLng!, boarding.jeepLatAtBoard, boarding.jeepLngAtBoard);
    commuterMoved = distanceMeters(reading.lat, reading.lng, boarding.boardedLat, boarding.boardedLng);
  }
  const jeepTravelled = jeepMoved >= moveNeeded;
  const tolerance = reading.accuracy! + 20;
  // Together: the jeepney has gone the distance, this phone covered most of it
  // too, and is still right beside it.
  const together = jeepTravelled && commuterMoved >= jeepMoved * 0.6 - tolerance && distance <= 50 + reading.accuracy!;
  // Left behind: the jeepney has gone the distance and this phone barely moved.
  const leftBehind = jeepTravelled && commuterMoved < jeepMoved * 0.4 - tolerance;

  if (together) {
    await prisma.tripBoarding.updateMany({
      where: { id: boarding.id, alightedAt: null },
      data: { ridingVerifiedAt: now, awayReadings: 0, awaySince: null, lastPresenceAt: now },
    });
    return { status: 'ON_BOARD', away: 0, required, verified: true };
  }

  if (distance <= limit && !leftBehind) {
    if (boarding.awayReadings > 0 || boarding.awaySince) {
      await prisma.tripBoarding.updateMany({
        where: { id: boarding.id, alightedAt: null },
        data: { awayReadings: 0, awaySince: null, lastPresenceAt: now },
      });
    } else {
      await prisma.tripBoarding.updateMany({ where: { id: boarding.id, alightedAt: null }, data: { lastPresenceAt: now } });
    }
    return { status: 'ON_BOARD', away: 0, required };
  }

  // Far from the jeepney.
  const awaySince = boarding.awaySince ?? now;
  const away = boarding.awayReadings + 1;
  const awaySeconds = (now.getTime() - awaySince.getTime()) / 1000;
  const release = away >= required && awaySeconds >= (settings.presenceReleaseMinSeconds as number);

  if (!release) {
    await prisma.tripBoarding.updateMany({
      where: { id: boarding.id, alightedAt: null },
      data: { awayReadings: away, awaySince },
    });
    return { status: 'ON_BOARD', away, required };
  }

  // Same guard as the commuter's own cancel: if the ride already ended, that wins.
  const closed = await prisma.tripBoarding.updateMany({
    where: { id: boarding.id, alightedAt: null, status: 'BOARDED' },
    data: {
      status: 'CANCELLED',
      cancelledAt: now,
      alightedAt: now,
      releasedReason: 'NOT_ON_BOARD',
      awayReadings: away,
      awaySince,
    },
  });
  if (closed.count === 0) return { status: 'NOT_BOARDED' };

  await notifyCommuter({
    recipientId: commuterId,
    title: 'Removed from jeepney',
    message: "We could tell you weren't on the jeepney, so you're no longer counted as a passenger. Board again if you do ride.",
    type: 'BOARDING_RELEASED',
    referenceId: boarding.tripId,
  });

  return { status: 'RELEASED', tripId: boarding.tripId, boardingId: boarding.id };
}

/**
 * Backstop for commuters who vanish after boarding (phone off, app killed, no
 * signal) — nobody is left to send presence readings. Anyone still NOT seen
 * travelling with the jeepney after [presenceUnverifiedTimeoutSeconds], while
 * the jeepney has driven at least [presenceUnverifiedMinTravelMeters] from the
 * boarding point, is released. A real rider whose app is working is verified
 * within the first ~100 m, so this only ever hits boardings with no evidence at
 * all. Rows from before this feature (no baseline) are never touched.
 */
export async function releaseUnverifiedBoardings(): Promise<number> {
  const settings = await getSettings();
  const now = new Date();
  const cutoff = new Date(now.getTime() - (settings.presenceUnverifiedTimeoutSeconds as number) * 1000);
  const candidates = await prisma.tripBoarding.findMany({
    where: {
      status: 'BOARDED',
      alightedAt: null,
      ridingVerifiedAt: null,
      boardedAt: { lt: cutoff },
      jeepLatAtBoard: { not: null },
      jeepLngAtBoard: { not: null },
    },
    take: 200,
  });
  if (candidates.length === 0) return 0;

  const trips = await prisma.trip.findMany({
    where: { id: { in: [...new Set(candidates.map((b) => b.tripId))] }, status: 'ACTIVE' },
    select: { id: true, currentLat: true, currentLng: true },
  });
  const tripById = new Map(trips.map((t) => [t.id, t]));
  const minTravel = settings.presenceUnverifiedMinTravelMeters as number;

  let released = 0;
  for (const b of candidates) {
    const trip = tripById.get(b.tripId);
    if (!trip || trip.currentLat === null || trip.currentLng === null) continue;
    if (distanceMeters(trip.currentLat, trip.currentLng, b.jeepLatAtBoard!, b.jeepLngAtBoard!) < minTravel) continue;

    const closed = await prisma.tripBoarding.updateMany({
      where: { id: b.id, alightedAt: null, status: 'BOARDED', ridingVerifiedAt: null },
      data: { status: 'CANCELLED', cancelledAt: now, alightedAt: now, releasedReason: 'NO_PRESENCE' },
    });
    if (closed.count === 0) continue;
    released++;
    await notifyCommuter({
      recipientId: b.commuterId,
      title: 'Removed from jeepney',
      message: "We couldn't confirm you were riding the jeepney, so you're no longer counted as a passenger. Board again if you are still on it.",
      type: 'BOARDING_RELEASED',
      referenceId: b.tripId,
    });
  }
  return released;
}
