import type { Prisma } from '@prisma/client';

import { prisma } from './prisma';

/** Append-only record of who changed what on disciplinary/operational data.
 * Pass `tx` to write it in the same transaction as the change itself. */
export async function writeAudit(
  entry: {
    actorType: 'admin' | 'driver' | 'commuter' | 'system';
    actorId?: string | null;
    action: string;
    targetType: string;
    targetId?: string | null;
    details?: Prisma.InputJsonValue;
  },
  tx: Prisma.TransactionClient | typeof prisma = prisma,
) {
  await tx.auditLog.create({
    data: {
      actorType: entry.actorType,
      actorId: entry.actorId ?? null,
      action: entry.action,
      targetType: entry.targetType,
      targetId: entry.targetId ?? null,
      details: entry.details,
    },
  });
}
