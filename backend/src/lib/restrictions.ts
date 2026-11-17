import type { Prisma, ShortTripIncidentStatus } from '@prisma/client';

import { prisma } from './prisma';
import { writeAudit } from './audit';
import { getSettings } from './settings';

type Tx = Prisma.TransactionClient | typeof prisma;

/** The restriction currently blocking this driver from starting a trip, if
 * any. Judged against the server clock only — nothing the client sends. */
export async function getActiveRestriction(driverId: string, tx: Tx = prisma) {
  const now = new Date();
  return tx.driverRestriction.findFirst({
    where: { driverId, liftedAt: null, startsAt: { lte: now }, expiresAt: { gt: now } },
    orderBy: { expiresAt: 'desc' },
  });
}

export function toPublicRestriction(r: {
  id: string;
  reason: string;
  startsAt: Date;
  expiresAt: Date;
  durationMinutes: number;
}) {
  const now = new Date();
  return {
    id: r.id,
    reason: r.reason,
    startsAt: r.startsAt,
    expiresAt: r.expiresAt,
    durationMinutes: r.durationMinutes,
    serverNow: now,
    secondsRemaining: Math.max(0, Math.ceil((r.expiresAt.getTime() - now.getTime()) / 1000)),
  };
}

/** Incident statuses that count toward a restriction under current settings. */
async function qualifyingStatuses(): Promise<ShortTripIncidentStatus[]> {
  const { shortTripCountOnlyConfirmed } = await getSettings();
  return shortTripCountOnlyConfirmed
    ? ['CONFIRMED']
    : ['PENDING_EXPLANATION', 'EXPLAINED', 'UNDER_REVIEW', 'CONFIRMED'];
}

/**
 * Called whenever an incident is created or changes status. If the driver now
 * has enough qualifying incidents that haven't already been used for a
 * restriction, applies a restriction (attributed to [actor]) and marks those
 * incidents as used. DISMISSED / DUPLICATE incidents never qualify. Returns
 * the new restriction, or null.
 *
 * "Used" matters: without it every later confirmation would re-trigger on the
 * same old incidents. It does NOT reset anything on logout/device change —
 * it's all server-side.
 */
export async function applyRestrictionIfNeeded(
  tx: Prisma.TransactionClient,
  driverId: string,
  actor: { type: 'admin' | 'system'; id: string | null },
) {
  // One evaluation per driver at a time, so two reviewers confirming incidents
  // together can't both consume the same incidents into two restrictions.
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${driverId}))`;

  const settings = await getSettings();
  const threshold = settings.shortTripRestrictionThreshold as number;
  const minutes = settings.shortTripRestrictionMinutes as number;
  const statuses = await qualifyingStatuses();

  const incidents = await tx.shortTripIncident.findMany({
    where: { driverId, restrictionId: null, status: { in: statuses } },
    orderBy: { occurredAt: 'asc' },
    select: { id: true },
  });
  if (incidents.length < threshold) return null;

  const startsAt = new Date();
  const expiresAt = new Date(startsAt.getTime() + minutes * 60_000);
  const incidentIds = incidents.map((i) => i.id);
  const restriction = await tx.driverRestriction.create({
    data: {
      driverId,
      reason: `${incidents.length} short-tripping occurrences on record (limit ${threshold}). You cannot start a new trip until the restriction ends.`,
      startsAt,
      expiresAt,
      durationMinutes: minutes,
      appliedById: actor.id,
      incidentIds,
    },
  });
  await tx.shortTripIncident.updateMany({ where: { id: { in: incidentIds } }, data: { restrictionId: restriction.id } });
  await writeAudit(
    {
      actorType: actor.type,
      actorId: actor.id,
      action: 'RESTRICTION_APPLIED',
      targetType: 'driver',
      targetId: driverId,
      details: { restrictionId: restriction.id, incidentIds, durationMinutes: minutes, threshold },
    },
    tx,
  );
  return restriction;
}

/**
 * An incident that was already counted into a restriction has been corrected
 * (dismissed / marked duplicate). Releases it, and if the restriction no
 * longer has enough incidents behind it, lifts it — so a mistaken record
 * can't keep a driver locked out.
 */
export async function releaseIncidentFromRestriction(
  tx: Prisma.TransactionClient,
  incident: { id: string; restrictionId: string | null },
  actorId: string | null,
) {
  if (!incident.restrictionId) return;
  const restrictionId = incident.restrictionId;
  await tx.shortTripIncident.update({ where: { id: incident.id }, data: { restrictionId: null } });

  const restriction = await tx.driverRestriction.findUnique({ where: { id: restrictionId } });
  if (!restriction || restriction.liftedAt) return;

  const { shortTripRestrictionThreshold } = await getSettings();
  const remaining = await tx.shortTripIncident.count({ where: { restrictionId } });
  if (remaining < (shortTripRestrictionThreshold as number)) {
    await tx.driverRestriction.update({
      where: { id: restrictionId },
      data: { liftedAt: new Date(), liftedById: actorId, liftNote: 'A qualifying incident was corrected on review.' },
    });
    await writeAudit(
      {
        actorType: 'admin',
        actorId,
        action: 'RESTRICTION_LIFTED_AFTER_CORRECTION',
        targetType: 'driver',
        targetId: restriction.driverId,
        details: { restrictionId, correctedIncidentId: incident.id },
      },
      tx,
    );
  }
}

/** Evaluates a driver on its own (outside a caller's transaction). */
export async function evaluateRestriction(driverId: string, actor: { type: 'admin' | 'system'; id: string | null }) {
  return prisma.$transaction((tx) => applyRestrictionIfNeeded(tx, driverId, actor));
}
