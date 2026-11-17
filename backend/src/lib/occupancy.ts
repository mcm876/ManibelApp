import type { Prisma } from '@prisma/client';

import { prisma } from './prisma';
import { getSettings } from './settings';

export type OccupancyStatus = 'NORMAL' | 'NEARLY_FULL' | 'FULL' | 'UNKNOWN';

export interface Occupancy {
  tripId: string;
  vehicleId: string | null;
  plateNumber: string | null;
  appPassengers: number;
  manualPassengers: number;
  totalPassengers: number;
  /** null = the trip has no vehicle/capacity on record (pre-vehicle trips). */
  seatingCapacity: number | null;
  remainingSeats: number | null;
  status: OccupancyStatus;
  nearFullThresholdPercent: number;
  /** Total at which NEARLY_FULL starts (null without a capacity). */
  nearFullAtPassengers: number | null;
}

type Tx = Prisma.TransactionClient | typeof prisma;

export function occupancyStatus(total: number, capacity: number | null, nearFullPercent: number): OccupancyStatus {
  if (capacity === null) return 'UNKNOWN';
  if (total >= capacity) return 'FULL';
  if (total >= Math.ceil((capacity * nearFullPercent) / 100)) return 'NEARLY_FULL';
  return 'NORMAL';
}

/** Takes a row lock on the trip until the surrounding transaction ends, so
 * two boardings / manual adds can't both read "1 seat left" and both succeed. */
export async function lockTrip(tx: Prisma.TransactionClient, tripId: string) {
  await tx.$queryRaw`SELECT "id" FROM "Trip" WHERE "id" = ${tripId} FOR UPDATE`;
}

/**
 * Occupancy of one trip. App passengers are derived from open BOARDED
 * TripBoarding rows (a party of N counts N seats) — never stored, so they
 * can't drift from the boardings. Manual passengers are Trip.manualPassengers.
 * Call inside a transaction after [lockTrip] when the result gates a write.
 */
export async function getOccupancy(tx: Tx, tripId: string): Promise<Occupancy | null> {
  const trip = await tx.trip.findUnique({
    where: { id: tripId },
    select: { id: true, vehicleId: true, plateNumber: true, manualPassengers: true, vehicle: { select: { seatingCapacity: true, plateNumber: true } } },
  });
  if (!trip) return null;

  const rows = await tx.$queryRaw<{ total: bigint }[]>`
    SELECT COALESCE(SUM(COALESCE("riders", 1)), 0) AS total
    FROM "TripBoarding"
    WHERE "tripId" = ${tripId} AND "alightedAt" IS NULL AND "status" = 'BOARDED'`;
  const appPassengers = Number(rows[0]?.total ?? 0);

  const { nearFullThresholdPercent } = await getSettings();
  const percent = nearFullThresholdPercent as number;
  const capacity = trip.vehicle?.seatingCapacity ?? null;
  const total = appPassengers + trip.manualPassengers;

  return {
    tripId,
    vehicleId: trip.vehicleId,
    plateNumber: trip.vehicle?.plateNumber ?? trip.plateNumber,
    appPassengers,
    manualPassengers: trip.manualPassengers,
    totalPassengers: total,
    seatingCapacity: capacity,
    remainingSeats: capacity === null ? null : Math.max(0, capacity - total),
    status: occupancyStatus(total, capacity, percent),
    nearFullThresholdPercent: percent,
    nearFullAtPassengers: capacity === null ? null : Math.ceil((capacity * percent) / 100),
  };
}

/** Records the highest occupancy reached (reports). Inside the same tx. */
export async function bumpPeakOccupancy(tx: Prisma.TransactionClient, tripId: string, total: number) {
  await tx.trip.updateMany({ where: { id: tripId, peakOccupancy: { lt: total } }, data: { peakOccupancy: total } });
}

export const OCCUPANCY_MESSAGES: Record<OccupancyStatus, string | null> = {
  NORMAL: null,
  NEARLY_FULL: 'Nearly full — only a few seats left.',
  FULL: 'FULL — no more passengers can be added.',
  UNKNOWN: null,
};
