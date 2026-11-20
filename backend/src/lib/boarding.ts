import { Prisma, type BoardingRequest } from '@prisma/client';

import { prisma } from './prisma';
import { bumpPeakOccupancy, getOccupancy, lockTrip } from './occupancy';
import { getSettings, type Settings } from './settings';
import { distanceMeters } from '../utils/geo';

/**
 * GPS-verified boarding. Pressing Board only creates a PENDING BoardingRequest;
 * a passenger (TripBoarding) exists only once enough consecutive commuter
 * readings have matched the driver's position, and the jeepney still has room
 * at the moment of confirmation (re-checked under a row lock).
 *
 * Proximity is evidence of boarding, not proof — and it is used ONLY here.
 * Nothing re-checks it after confirmation, so passengers riding along with
 * the driver are never dropped from the count.
 */

export interface GpsReading {
  lat: number;
  lng: number;
  /** Horizontal accuracy radius reported by the phone, metres. */
  accuracy?: number;
  /** How old the phone's GPS fix already was when sent, seconds (device-side,
   * so it doesn't depend on the phone's clock agreeing with the server's). */
  fixAgeSeconds?: number;
}

interface StoredReading {
  receivedAt: string;
  lat: number;
  lng: number;
  accuracy: number | null;
  distance: number | null;
  ok: boolean;
  reason: string | null;
}

const FAILURE_MESSAGES: Record<string, string> = {
  TRIP_ENDED: "This jeepney's trip has ended.",
  JEEPNEY_FULL: 'This jeepney is full right now, so you could not be added.',
  VERIFICATION_TIMEOUT: 'Boarding verification timed out. You may retry.',
  TOO_FAR: 'You are too far from the jeepney to confirm boarding.',
  DRIVER_LOCATION_STALE: "We can't see this jeepney's live location right now, so boarding can't be confirmed. Try again in a moment.",
  DRIVER_LOCATION_MISSING: "We can't see this jeepney's live location right now, so boarding can't be confirmed. Try again in a moment.",
  GPS_STALE: 'Your phone gave an old location. Wait a few seconds for a fresh GPS fix and try again.',
  GPS_INACCURATE: 'Your GPS signal is too weak to confirm boarding. Move to an open area and try again.',
  CAPACITY_UNKNOWN: "This jeepney's seating capacity isn't set up yet, so boarding can't be confirmed.",
};

export function boardingMessage(code: string | null): string {
  return (code && FAILURE_MESSAGES[code]) || "Boarding couldn't be confirmed. Please try again.";
}

/** One word the app can switch on: distinguishes a confirmation from a failed
 * validation, a duplicate, a full jeepney and an expired request. */
export type BoardingOutcome = 'PENDING' | 'CONFIRMED' | 'DUPLICATE' | 'FULL' | 'EXPIRED' | 'CANCELLED' | 'FAILED';

export function boardingOutcome(req: BoardingRequest): BoardingOutcome {
  if (req.status === 'PENDING') return 'PENDING';
  if (req.status === 'CONFIRMED') return 'CONFIRMED';
  if (req.status === 'CANCELLED') return 'CANCELLED';
  if (req.failureCode === 'JEEPNEY_FULL') return 'FULL';
  if (req.failureCode === 'VERIFICATION_TIMEOUT' || (req.resolvedAt && req.resolvedAt >= req.expiresAt)) return 'EXPIRED';
  return 'FAILED';
}

export function toBoardingRequestView(req: BoardingRequest, settings?: Settings) {
  const required = (settings?.boardingRequiredReadings as number | undefined) ?? null;
  const message =
    req.status === 'PENDING'
      ? 'Verifying that you are on the jeepney…'
      : req.status === 'CONFIRMED'
        ? "Boarding confirmed. You're on board."
        : req.status === 'CANCELLED'
          ? 'Boarding request cancelled.'
          : req.failureMessage ?? boardingMessage(req.failureCode);
  return {
    requestId: req.id,
    status: req.status,
    outcome: boardingOutcome(req),
    message,
    tripId: req.tripId,
    boardingId: req.boardingId,
    riders: req.riders,
    failureCode: req.failureCode,
    confirmedReadings: req.consecutiveOk,
    requiredReadings: required,
    expiresAt: req.expiresAt,
    serverNow: new Date(),
  };
}

async function failRequest(id: string, code: string) {
  await prisma.boardingRequest.updateMany({
    where: { id, status: 'PENDING' },
    data: { status: 'FAILED', failureCode: code, failureMessage: boardingMessage(code), resolvedAt: new Date() },
  });
}

/** Last reason a reading was rejected — drives the message when the window runs out. */
function lastFailureReason(readings: StoredReading[]): string {
  for (let i = readings.length - 1; i >= 0; i--) {
    if (!readings[i].ok && readings[i].reason) return readings[i].reason!;
  }
  return 'VERIFICATION_TIMEOUT';
}

/**
 * Feeds one commuter GPS reading into a pending request and, if the evidence
 * is now sufficient, confirms it. Safe to call repeatedly and concurrently:
 * confirmation re-claims the request inside the capacity transaction.
 */
export async function submitBoardingReading(requestId: string, commuterId: string, reading: GpsReading) {
  const settings = await getSettings();
  const request = await prisma.boardingRequest.findUnique({ where: { id: requestId } });
  if (!request || request.commuterId !== commuterId) return null;
  if (request.status !== 'PENDING') return toBoardingRequestView(request, settings);

  const now = new Date();
  const readings = (Array.isArray(request.readings) ? request.readings : []) as unknown as StoredReading[];

  const trip = await prisma.trip.findUnique({ where: { id: request.tripId } });
  if (!trip || trip.status !== 'ACTIVE') {
    await failRequest(request.id, 'TRIP_ENDED');
    return toBoardingRequestView((await prisma.boardingRequest.findUnique({ where: { id: request.id } }))!, settings);
  }

  // Judge this reading.
  let distance: number | null = null;
  let reason: string | null = null;
  const maxAcc = settings.boardingMaxAccuracyMeters as number;
  const maxFixAge = settings.boardingMaxFixAgeSeconds as number;
  const driverMaxAge = settings.boardingDriverMaxAgeSeconds as number;

  if (reading.fixAgeSeconds === undefined || reading.fixAgeSeconds > maxFixAge) {
    reason = 'GPS_STALE';
  } else if (reading.accuracy === undefined || reading.accuracy > maxAcc) {
    reason = 'GPS_INACCURATE';
  } else if (trip.currentLat === null || trip.currentLng === null || !trip.locationUpdatedAt) {
    reason = 'DRIVER_LOCATION_MISSING';
  } else if (now.getTime() - trip.locationUpdatedAt.getTime() > driverMaxAge * 1000) {
    reason = 'DRIVER_LOCATION_STALE';
  } else {
    distance = distanceMeters(reading.lat, reading.lng, trip.currentLat, trip.currentLng);
    const allowance = Math.min(reading.accuracy, settings.boardingAccuracyAllowanceMeters as number);
    if (distance > (settings.boardingProximityMeters as number) + allowance) reason = 'TOO_FAR';
  }
  const ok = reason === null;

  const stored: StoredReading = {
    receivedAt: now.toISOString(),
    lat: reading.lat,
    lng: reading.lng,
    accuracy: reading.accuracy ?? null,
    distance: distance === null ? null : Math.round(distance * 10) / 10,
    ok,
    reason,
  };
  const nextReadings = [...readings, stored].slice(-30);

  const expired = now > request.expiresAt;

  // The trailing run of good readings is the "validation window".
  let streak = 0;
  for (let i = nextReadings.length - 1; i >= 0 && nextReadings[i].ok; i--) streak++;
  const streakStart = streak > 0 ? new Date(nextReadings[nextReadings.length - streak].receivedAt) : null;
  const windowSeconds = streakStart ? (now.getTime() - streakStart.getTime()) / 1000 : 0;
  const required = settings.boardingRequiredReadings as number;
  const enough = !expired && streak >= required && windowSeconds >= (settings.boardingMinWindowSeconds as number);


  if (!enough) {
    await prisma.boardingRequest.updateMany({
      where: { id: request.id, status: 'PENDING' },
      data: { readings: nextReadings as unknown as Prisma.InputJsonValue, consecutiveOk: streak },
    });
    if (expired) await failRequest(request.id, lastFailureReason(nextReadings));
    return toBoardingRequestView((await prisma.boardingRequest.findUnique({ where: { id: request.id } }))!, settings);
  }

  // Confirm — under the trip lock so concurrent boardings can't pass the same seat.
  const outcome = await prisma.$transaction(async (tx) => {
    await lockTrip(tx, request.tripId);

    const claimed = await tx.boardingRequest.updateMany({
      where: { id: request.id, status: 'PENDING' },
      data: { readings: nextReadings as unknown as Prisma.InputJsonValue, consecutiveOk: streak },
    });
    if (claimed.count === 0) return { kind: 'already' as const };

    const lockedTrip = await tx.trip.findUnique({ where: { id: request.tripId }, select: { status: true, vehicleId: true } });
    if (!lockedTrip || lockedTrip.status !== 'ACTIVE') return { kind: 'fail' as const, code: 'TRIP_ENDED' };

    // Never double-count a commuter that already has an open ride on this trip.
    const existing = await tx.tripBoarding.findFirst({
      where: { tripId: request.tripId, commuterId, alightedAt: null },
      select: { id: true },
    });
    if (existing) {
      const done = await tx.boardingRequest.update({
        where: { id: request.id },
        data: { status: 'CONFIRMED', boardingId: existing.id, resolvedAt: now },
      });
      return { kind: 'ok' as const, request: done };
    }

    const occupancy = await getOccupancy(tx, request.tripId, settings);
    if (lockedTrip.vehicleId) {
      if (!occupancy || occupancy.seatingCapacity === null) return { kind: 'fail' as const, code: 'CAPACITY_UNKNOWN' };
      if (occupancy.totalPassengers + request.riders > occupancy.seatingCapacity) {
        return { kind: 'fail' as const, code: 'JEEPNEY_FULL' };
      }
    }

    const boarding = await tx.tripBoarding.create({
      data: { tripId: request.tripId, commuterId, riders: request.riders, requestId: request.id },
    });
    const done = await tx.boardingRequest.update({
      where: { id: request.id },
      data: { status: 'CONFIRMED', boardingId: boarding.id, resolvedAt: now },
    });
    if (occupancy) await bumpPeakOccupancy(tx, request.tripId, occupancy.totalPassengers + request.riders);
    // This commuter's need is fulfilled — same as the old immediate board.
    await tx.demandSignal.updateMany({ where: { commuterId, fulfilledAt: null }, data: { fulfilledAt: now } });
    return { kind: 'ok' as const, request: done };
  });

  if (outcome.kind === 'fail') {
    await failRequest(request.id, outcome.code);
  }
  return toBoardingRequestView((await prisma.boardingRequest.findUnique({ where: { id: request.id } }))!, settings);
}

/** Fails every PENDING request whose time is up, even if the commuter's app
 * stopped sending readings (closed, crashed, lost signal). Cheap — indexed. */
export async function expireStaleRequests(): Promise<number> {
  const stale = await prisma.boardingRequest.findMany({
    where: { status: 'PENDING', expiresAt: { lt: new Date() } },
    select: { id: true, readings: true },
    take: 500,
  });
  for (const req of stale) {
    const readings = (Array.isArray(req.readings) ? req.readings : []) as unknown as StoredReading[];
    await failRequest(req.id, lastFailureReason(readings));
  }
  return stale.length;
}

export function startBoardingExpiryJob() {
  const timer = setInterval(() => {
    expireStaleRequests().catch((err) => console.error('[boarding] expiry sweep failed', err));
  }, 30_000);
  timer.unref();
}

/** Expires a stale PENDING request on read, so a client polling status sees
 * the truth even if it stopped sending readings. */
export async function expireIfDue(requestId: string) {
  const req = await prisma.boardingRequest.findUnique({ where: { id: requestId } });
  if (req && req.status === 'PENDING' && new Date() > req.expiresAt) {
    const readings = (Array.isArray(req.readings) ? req.readings : []) as unknown as StoredReading[];
    await failRequest(req.id, lastFailureReason(readings));
  }
}
