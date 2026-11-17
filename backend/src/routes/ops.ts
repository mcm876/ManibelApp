import { Router } from 'express';
import type { Request } from 'express';
import { Prisma } from '@prisma/client';
import { z } from 'zod';

import { prisma } from '../lib/prisma';
import { requireAuth, requireStaff, type StaffRole } from '../middleware/auth';
import { isValidPlateNumber, normalizePlateNumber } from '../utils/plate';
import { formatDateOnly, manilaDayKey, manilaMidnight } from '../utils/date';
import { writeAudit } from '../lib/audit';
import { getOccupancy } from '../lib/occupancy';
import { SETTING_DEFS, getSettings, invalidateSettingsCache, validateSettingValue, type SettingKey } from '../lib/settings';
import {
  applyRestrictionIfNeeded,
  getActiveRestriction,
  releaseIncidentFromRestriction,
  toPublicRestriction,
} from '../lib/restrictions';
import { notifyDriver } from '../utils/notify';

/**
 * Fleet operations for the staff roles — vehicles, driver↔vehicle
 * assignments, trip/occupancy monitoring, short-tripping incidents,
 * restrictions, statuses and reports. One router serves every role; what a
 * caller sees is decided here, on the server:
 *   MAIN_ADMIN / ADMIN : everything
 *   OPERATOR           : only drivers with Driver.operatorId = them and
 *                        vehicles with Vehicle.operatorId = them
 *   MANIBELA           : everything, read-only (except reviewing incidents)
 */
const router = Router();
router.use(requireAuth('admin'), requireStaff());

const FLEET_WRITERS: StaffRole[] = ['MAIN_ADMIN', 'ADMIN', 'OPERATOR'];
const SETTINGS_WRITERS: StaffRole[] = ['MAIN_ADMIN', 'ADMIN'];
const INCIDENT_REVIEWERS: StaffRole[] = ['MAIN_ADMIN', 'ADMIN', 'OPERATOR', 'MANIBELA'];

function can(req: Request, roles: StaffRole[]) {
  return roles.includes(req.staff!.role);
}
function deny(res: import('express').Response, message = 'Your role is not allowed to do this.') {
  res.status(403).json({ error: message, code: 'ROLE_FORBIDDEN' });
}
const isOperator = (req: Request) => req.staff!.role === 'OPERATOR';
const idParam = (req: Request, name = 'id'): string => {
  const v = req.params[name];
  return Array.isArray(v) ? v[0] : v;
};

/** Extra `where` that limits drivers to what this caller may see. */
const driverScope = (req: Request): Prisma.DriverWhereInput => (isOperator(req) ? { operatorId: req.staff!.id } : {});
const vehicleScope = (req: Request): Prisma.VehicleWhereInput => (isOperator(req) ? { operatorId: req.staff!.id } : {});

async function scopedDriver(req: Request, id: string) {
  return prisma.driver.findFirst({ where: { id, ...driverScope(req) } });
}
async function scopedVehicle(req: Request, id: string) {
  return prisma.vehicle.findFirst({ where: { id, ...vehicleScope(req) } });
}
/** Driver ids visible to the caller (null = no restriction). */
async function visibleDriverIds(req: Request): Promise<string[] | null> {
  if (!isOperator(req)) return null;
  const rows = await prisma.driver.findMany({ where: { operatorId: req.staff!.id }, select: { id: true } });
  return rows.map((r) => r.id);
}

const pageSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(25),
});

// ---------------------------------------------------------------------------
// SETTINGS — the configurable, not-yet-approved business rules.
// ---------------------------------------------------------------------------
router.get('/settings', async (_req, res, next) => {
  try {
    const values = await getSettings();
    const rows = await prisma.systemSetting.findMany({ select: { key: true, updatedAt: true, updatedById: true } });
    const meta = new Map(rows.map((r) => [r.key, r]));
    res.json({
      settings: (Object.keys(SETTING_DEFS) as SettingKey[]).map((key) => ({
        key,
        ...SETTING_DEFS[key],
        value: values[key],
        isDefault: !meta.has(key),
        updatedAt: meta.get(key)?.updatedAt ?? null,
      })),
    });
  } catch (err) {
    next(err);
  }
});

router.put('/settings', async (req, res, next) => {
  try {
    if (!can(req, SETTINGS_WRITERS)) return deny(res);
    const body = z.object({ values: z.record(z.string(), z.unknown()) }).parse(req.body);

    const updates: { key: SettingKey; value: number | boolean | null }[] = [];
    for (const [key, raw] of Object.entries(body.values)) {
      if (!(key in SETTING_DEFS)) {
        res.status(400).json({ error: `Unknown setting: ${key}` });
        return;
      }
      try {
        updates.push({ key: key as SettingKey, value: validateSettingValue(key as SettingKey, raw) });
      } catch (e) {
        res.status(400).json({ error: e instanceof Error ? e.message : 'Invalid value.' });
        return;
      }
    }

    await prisma.$transaction(async (tx) => {
      for (const u of updates) {
        await tx.systemSetting.upsert({
          where: { key: u.key },
          create: { key: u.key, value: u.value as Prisma.InputJsonValue, updatedById: req.staff!.id },
          update: { value: u.value as Prisma.InputJsonValue, updatedById: req.staff!.id },
        });
      }
      await writeAudit(
        {
          actorType: 'admin',
          actorId: req.staff!.id,
          action: 'SETTINGS_UPDATED',
          targetType: 'settings',
          details: Object.fromEntries(updates.map((u) => [u.key, u.value])) as Prisma.InputJsonValue,
        },
        tx,
      );
    });
    invalidateSettingsCache();
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

// Operator accounts, for assigning ownership.
router.get('/operators', async (req, res, next) => {
  try {
    if (isOperator(req)) return deny(res);
    const operators = await prisma.admin.findMany({
      where: { role: 'OPERATOR' },
      select: { id: true, fullName: true, email: true, isActive: true },
      orderBy: { fullName: 'asc' },
    });
    res.json({ operators });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// VEHICLES
// ---------------------------------------------------------------------------
const capacitySchema = z.number().int().min(1).max(100);

function vehicleView(
  v: {
    id: string;
    plateNumber: string;
    seatingCapacity: number | null;
    operatorId: string | null;
    isActive: boolean;
    notes: string | null;
    createdAt: Date;
  },
  extra: {
    operatorName?: string | null;
    drivers?: { assignmentId: string; driverId: string; fullName: string }[];
    activeTrip?: { id: string; driverName: string } | null;
  } = {},
) {
  return {
    id: v.id,
    plateNumber: v.plateNumber,
    seatingCapacity: v.seatingCapacity,
    capacityConfigured: v.seatingCapacity !== null,
    operatorId: v.operatorId,
    operatorName: extra.operatorName ?? null,
    isActive: v.isActive,
    notes: v.notes,
    createdAt: v.createdAt,
    assignedDrivers: extra.drivers ?? [],
    activeTrip: extra.activeTrip ?? null,
  };
}

router.get('/vehicles', async (req, res, next) => {
  try {
    const q = pageSchema.extend({ search: z.string().trim().min(1).optional(), missingCapacity: z.enum(['1']).optional() }).parse(req.query);
    const where: Prisma.VehicleWhereInput = {
      ...vehicleScope(req),
      ...(q.search ? { plateNumber: { contains: normalizePlateNumber(q.search) || q.search, mode: 'insensitive' } } : {}),
      ...(q.missingCapacity ? { seatingCapacity: null } : {}),
    };
    const [vehicles, total] = await Promise.all([
      prisma.vehicle.findMany({
        where,
        orderBy: { plateNumber: 'asc' },
        skip: (q.page - 1) * q.pageSize,
        take: q.pageSize,
        include: { assignments: { where: { revokedAt: null } } },
      }),
      prisma.vehicle.count({ where }),
    ]);

    const driverIds = [...new Set(vehicles.flatMap((v) => v.assignments.map((a) => a.driverId)))];
    const operatorIds = [...new Set(vehicles.map((v) => v.operatorId).filter((x): x is string => !!x))];
    const [drivers, operators, activeTrips] = await Promise.all([
      prisma.driver.findMany({ where: { id: { in: driverIds } }, select: { id: true, fullName: true } }),
      prisma.admin.findMany({ where: { id: { in: operatorIds } }, select: { id: true, fullName: true } }),
      prisma.trip.findMany({ where: { vehicleId: { in: vehicles.map((v) => v.id) }, status: 'ACTIVE' }, select: { id: true, vehicleId: true, driverId: true } }),
    ]);
    const driverName = new Map(drivers.map((d) => [d.id, d.fullName]));
    const opName = new Map(operators.map((o) => [o.id, o.fullName]));
    const tripByVehicle = new Map(activeTrips.map((t) => [t.vehicleId, t]));

    res.json({
      vehicles: vehicles.map((v) =>
        vehicleView(v, {
          operatorName: v.operatorId ? opName.get(v.operatorId) ?? null : null,
          drivers: v.assignments.map((a) => ({ assignmentId: a.id, driverId: a.driverId, fullName: driverName.get(a.driverId) ?? 'Unknown' })),
          activeTrip: tripByVehicle.has(v.id)
            ? { id: tripByVehicle.get(v.id)!.id, driverName: driverName.get(tripByVehicle.get(v.id)!.driverId) ?? 'Unknown' }
            : null,
        }),
      ),
      currentPage: q.page,
      pageSize: q.pageSize,
      totalVehicles: total,
      totalPages: Math.max(1, Math.ceil(total / q.pageSize)),
    });
  } catch (err) {
    next(err);
  }
});

const createVehicleSchema = z.object({
  plateNumber: z.string().trim().min(1),
  seatingCapacity: capacitySchema.nullable().optional(),
  operatorId: z.string().trim().min(1).nullable().optional(),
  notes: z.string().trim().max(500).optional(),
});

router.post('/vehicles', async (req, res, next) => {
  try {
    if (!can(req, FLEET_WRITERS)) return deny(res);
    const body = createVehicleSchema.parse(req.body);
    const plateNumber = normalizePlateNumber(body.plateNumber);
    if (!isValidPlateNumber(plateNumber)) {
      res.status(400).json({ error: 'Enter a valid plate number (3 letters followed by 3 or 4 digits).' });
      return;
    }
    // An operator's vehicles are always its own; admins choose the owner.
    const operatorId = isOperator(req) ? req.staff!.id : body.operatorId ?? null;
    if (operatorId && !(await prisma.admin.findFirst({ where: { id: operatorId, role: 'OPERATOR' } }))) {
      res.status(400).json({ error: 'That operator does not exist.' });
      return;
    }
    if (await prisma.vehicle.findUnique({ where: { plateNumber } })) {
      res.status(409).json({ error: `A vehicle with plate ${plateNumber} already exists.` });
      return;
    }
    const vehicle = await prisma.vehicle.create({
      data: { plateNumber, seatingCapacity: body.seatingCapacity ?? null, operatorId, notes: body.notes ?? null },
    });
    await writeAudit({
      actorType: 'admin',
      actorId: req.staff!.id,
      action: 'VEHICLE_CREATED',
      targetType: 'vehicle',
      targetId: vehicle.id,
      details: { plateNumber, seatingCapacity: vehicle.seatingCapacity },
    });
    res.status(201).json({ vehicle: vehicleView(vehicle) });
  } catch (err) {
    next(err);
  }
});

const updateVehicleSchema = z.object({
  seatingCapacity: capacitySchema.optional(),
  isActive: z.boolean().optional(),
  notes: z.string().trim().max(500).nullable().optional(),
  operatorId: z.string().trim().min(1).nullable().optional(),
});

router.patch('/vehicles/:id', async (req, res, next) => {
  try {
    if (!can(req, FLEET_WRITERS)) return deny(res);
    const body = updateVehicleSchema.parse(req.body);
    const vehicle = await scopedVehicle(req, idParam(req));
    if (!vehicle) {
      res.status(404).json({ error: 'Vehicle not found.' });
      return;
    }
    if (body.operatorId !== undefined && isOperator(req)) return deny(res, 'Only an administrator can change a vehicle\'s operator.');

    const activeTrip = await prisma.trip.findFirst({ where: { vehicleId: vehicle.id, status: 'ACTIVE' }, select: { id: true } });
    if (body.seatingCapacity !== undefined && activeTrip) {
      const occ = await getOccupancy(prisma, activeTrip.id);
      if (occ && body.seatingCapacity < occ.totalPassengers) {
        res.status(409).json({
          error: `This jeepney currently has ${occ.totalPassengers} passengers on board. Capacity cannot be set below that.`,
          code: 'CAPACITY_BELOW_OCCUPANCY',
        });
        return;
      }
    }
    if (body.isActive === false && activeTrip) {
      res.status(409).json({ error: 'This jeepney is on an active trip and cannot be deactivated yet.', code: 'VEHICLE_IN_USE' });
      return;
    }
    if (body.operatorId && !(await prisma.admin.findFirst({ where: { id: body.operatorId, role: 'OPERATOR' } }))) {
      res.status(400).json({ error: 'That operator does not exist.' });
      return;
    }

    const updated = await prisma.vehicle.update({
      where: { id: vehicle.id },
      data: {
        ...(body.seatingCapacity !== undefined ? { seatingCapacity: body.seatingCapacity } : {}),
        ...(body.isActive !== undefined ? { isActive: body.isActive } : {}),
        ...(body.notes !== undefined ? { notes: body.notes } : {}),
        ...(body.operatorId !== undefined ? { operatorId: body.operatorId } : {}),
      },
    });
    await writeAudit({
      actorType: 'admin',
      actorId: req.staff!.id,
      action: 'VEHICLE_UPDATED',
      targetType: 'vehicle',
      targetId: vehicle.id,
      details: { before: { seatingCapacity: vehicle.seatingCapacity, isActive: vehicle.isActive, operatorId: vehicle.operatorId }, after: body },
    });
    res.json({ vehicle: vehicleView(updated) });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// DRIVERS (fleet view — no KYC photos or personal documents here)
// ---------------------------------------------------------------------------
async function driverRows(drivers: { id: string }[]) {
  const ids = drivers.map((d) => d.id);
  const [assignments, activeTrips, restrictions] = await Promise.all([
    prisma.driverVehicleAssignment.findMany({ where: { driverId: { in: ids }, revokedAt: null }, include: { vehicle: true } }),
    prisma.trip.findMany({ where: { driverId: { in: ids }, status: 'ACTIVE' } }),
    prisma.driverRestriction.findMany({
      where: { driverId: { in: ids }, liftedAt: null, expiresAt: { gt: new Date() }, startsAt: { lte: new Date() } },
    }),
  ]);
  const occupancies = new Map<string, Awaited<ReturnType<typeof getOccupancy>>>();
  await Promise.all(activeTrips.map(async (t) => occupancies.set(t.id, await getOccupancy(prisma, t.id))));
  return { assignments, activeTrips, restrictions, occupancies };
}

router.get('/drivers', async (req, res, next) => {
  try {
    const q = pageSchema.extend({
      search: z.string().trim().min(1).optional(),
      operationalStatus: z.enum(['ACTIVE', 'INACTIVE']).optional(),
      disciplinaryStatus: z.enum(['NONE', 'WARNING', 'UNDER_INVESTIGATION', 'SUSPENDED']).optional(),
      unassigned: z.enum(['1']).optional(),
    }).parse(req.query);

    const where: Prisma.DriverWhereInput = {
      ...driverScope(req),
      ...(q.operationalStatus ? { operationalStatus: q.operationalStatus } : {}),
      ...(q.disciplinaryStatus ? { disciplinaryStatus: q.disciplinaryStatus } : {}),
      ...(q.unassigned ? { operatorId: null } : {}),
      ...(q.search
        ? { OR: [{ fullName: { contains: q.search, mode: 'insensitive' } }, { driverId: { contains: q.search, mode: 'insensitive' } }, { plateNumber: { contains: q.search, mode: 'insensitive' } }] }
        : {}),
    };
    const [drivers, total] = await Promise.all([
      prisma.driver.findMany({ where, orderBy: { fullName: 'asc' }, skip: (q.page - 1) * q.pageSize, take: q.pageSize }),
      prisma.driver.count({ where }),
    ]);
    const { assignments, activeTrips, restrictions, occupancies } = await driverRows(drivers);
    const operatorIds = [...new Set(drivers.map((d) => d.operatorId).filter((x): x is string => !!x))];
    const operators = await prisma.admin.findMany({ where: { id: { in: operatorIds } }, select: { id: true, fullName: true } });
    const opName = new Map(operators.map((o) => [o.id, o.fullName]));

    res.json({
      drivers: drivers.map((d) => {
        const trip = activeTrips.find((t) => t.driverId === d.id);
        const occ = trip ? occupancies.get(trip.id) : null;
        const restriction = restrictions.find((r) => r.driverId === d.id);
        return {
          id: d.id,
          driverId: d.driverId,
          fullName: d.fullName,
          mobileNumber: d.mobileNumber,
          isActive: d.isActive,
          operationalStatus: d.operationalStatus,
          disciplinaryStatus: d.disciplinaryStatus,
          operatorId: d.operatorId,
          operatorName: d.operatorId ? opName.get(d.operatorId) ?? null : null,
          vehicles: assignments
            .filter((a) => a.driverId === d.id)
            .map((a) => ({ assignmentId: a.id, id: a.vehicleId, plateNumber: a.vehicle.plateNumber, seatingCapacity: a.vehicle.seatingCapacity })),
          activeTrip: trip
            ? { id: trip.id, plateNumber: trip.plateNumber, route: trip.route, startedAt: trip.startedAt, occupancy: occ }
            : null,
          restriction: restriction ? toPublicRestriction(restriction) : null,
        };
      }),
      currentPage: q.page,
      pageSize: q.pageSize,
      totalDrivers: total,
      totalPages: Math.max(1, Math.ceil(total / q.pageSize)),
    });
  } catch (err) {
    next(err);
  }
});

router.get('/drivers/:id', async (req, res, next) => {
  try {
    const driver = await scopedDriver(req, idParam(req));
    if (!driver) {
      res.status(404).json({ error: 'Driver not found.' });
      return;
    }
    const [{ assignments, activeTrips, restrictions, occupancies }, incidents, restrictionHistory, trips] = await Promise.all([
      driverRows([driver]),
      prisma.shortTripIncident.findMany({ where: { driverId: driver.id }, orderBy: { occurredAt: 'desc' }, take: 20 }),
      prisma.driverRestriction.findMany({ where: { driverId: driver.id }, orderBy: { createdAt: 'desc' }, take: 10 }),
      prisma.trip.findMany({ where: { driverId: driver.id, status: 'COMPLETED' }, orderBy: { startedAt: 'desc' }, take: 10 }),
    ]);
    const trip = activeTrips[0];
    res.json({
      driver: {
        id: driver.id,
        driverId: driver.driverId,
        fullName: driver.fullName,
        mobileNumber: driver.mobileNumber,
        isActive: driver.isActive,
        operationalStatus: driver.operationalStatus,
        disciplinaryStatus: driver.disciplinaryStatus,
        operatorId: driver.operatorId,
        vehicles: assignments.map((a) => ({ assignmentId: a.id, id: a.vehicleId, plateNumber: a.vehicle.plateNumber, seatingCapacity: a.vehicle.seatingCapacity })),
        activeTrip: trip ? { id: trip.id, plateNumber: trip.plateNumber, startedAt: trip.startedAt, occupancy: occupancies.get(trip.id) } : null,
        restriction: restrictions[0] ? toPublicRestriction(restrictions[0]) : null,
      },
      incidents,
      restrictionHistory,
      recentTrips: trips.map((t) => ({ id: t.id, plateNumber: t.plateNumber, route: t.route, startedAt: t.startedAt, endedAt: t.endedAt, peakOccupancy: t.peakOccupancy, capacitySnapshot: t.capacitySnapshot })),
    });
  } catch (err) {
    next(err);
  }
});

router.patch('/drivers/:id/operator', async (req, res, next) => {
  try {
    if (!can(req, SETTINGS_WRITERS)) return deny(res, 'Only an administrator can assign a driver to an operator.');
    const body = z.object({ operatorId: z.string().trim().min(1).nullable() }).parse(req.body);
    const driver = await prisma.driver.findUnique({ where: { id: idParam(req) } });
    if (!driver) {
      res.status(404).json({ error: 'Driver not found.' });
      return;
    }
    if (body.operatorId && !(await prisma.admin.findFirst({ where: { id: body.operatorId, role: 'OPERATOR' } }))) {
      res.status(400).json({ error: 'That operator does not exist.' });
      return;
    }
    await prisma.driver.update({ where: { id: driver.id }, data: { operatorId: body.operatorId } });
    await writeAudit({
      actorType: 'admin',
      actorId: req.staff!.id,
      action: 'DRIVER_OPERATOR_CHANGED',
      targetType: 'driver',
      targetId: driver.id,
      details: { from: driver.operatorId, to: body.operatorId },
    });
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

// Operating status and disciplinary status are separate on purpose: stopping
// work is INACTIVE and never implies a sanction, and complaints never change
// either automatically. A disciplinary change needs a recorded reason.
const driverStatusSchema = z.object({
  operationalStatus: z.enum(['ACTIVE', 'INACTIVE']).optional(),
  disciplinaryStatus: z.enum(['NONE', 'WARNING', 'UNDER_INVESTIGATION', 'SUSPENDED']).optional(),
  note: z.string().trim().max(1000).optional(),
});

router.patch('/drivers/:id/status', async (req, res, next) => {
  try {
    if (!can(req, FLEET_WRITERS)) return deny(res);
    const body = driverStatusSchema.parse(req.body);
    const driver = await scopedDriver(req, idParam(req));
    if (!driver) {
      res.status(404).json({ error: 'Driver not found.' });
      return;
    }
    if (body.disciplinaryStatus !== undefined && body.disciplinaryStatus !== 'NONE' && !body.note?.trim()) {
      res.status(400).json({ error: 'Please record the reason for this disciplinary status.' });
      return;
    }
    if (body.operationalStatus === 'INACTIVE') {
      const active = await prisma.trip.findFirst({ where: { driverId: driver.id, status: 'ACTIVE' }, select: { id: true } });
      if (active) {
        res.status(409).json({ error: 'This driver is on an active trip. Mark them inactive after the trip ends.' });
        return;
      }
    }
    const updated = await prisma.driver.update({
      where: { id: driver.id },
      data: {
        ...(body.operationalStatus ? { operationalStatus: body.operationalStatus } : {}),
        ...(body.disciplinaryStatus ? { disciplinaryStatus: body.disciplinaryStatus } : {}),
      },
    });
    await writeAudit({
      actorType: 'admin',
      actorId: req.staff!.id,
      action: 'DRIVER_STATUS_CHANGED',
      targetType: 'driver',
      targetId: driver.id,
      details: {
        operational: { from: driver.operationalStatus, to: updated.operationalStatus },
        disciplinary: { from: driver.disciplinaryStatus, to: updated.disciplinaryStatus },
        note: body.note ?? null,
      },
    });
    if (body.disciplinaryStatus && body.disciplinaryStatus !== driver.disciplinaryStatus) {
      await notifyDriver({
        recipientId: driver.id,
        title: 'Your driver status changed',
        message: `Your disciplinary status is now ${body.disciplinaryStatus.replace('_', ' ').toLowerCase()}.${body.note ? ` ${body.note}` : ''}`,
      });
    }
    res.json({ driver: { id: updated.id, operationalStatus: updated.operationalStatus, disciplinaryStatus: updated.disciplinaryStatus } });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// ASSIGNMENTS
// ---------------------------------------------------------------------------
router.post('/assignments', async (req, res, next) => {
  try {
    if (!can(req, FLEET_WRITERS)) return deny(res);
    const body = z.object({ driverId: z.string().trim().min(1), vehicleId: z.string().trim().min(1) }).parse(req.body);
    // Both sides must be inside the caller's scope — an operator can't hand
    // another operator's jeepney to its own driver, or vice versa.
    const [driver, vehicle] = await Promise.all([scopedDriver(req, body.driverId), scopedVehicle(req, body.vehicleId)]);
    if (!driver || !vehicle) {
      res.status(404).json({ error: 'Driver or vehicle not found.' });
      return;
    }
    if (!vehicle.isActive) {
      res.status(409).json({ error: 'This vehicle is inactive.' });
      return;
    }
    const existing = await prisma.driverVehicleAssignment.findFirst({
      where: { driverId: driver.id, vehicleId: vehicle.id, revokedAt: null },
    });
    if (existing) {
      res.status(409).json({ error: `${driver.fullName} is already assigned to ${vehicle.plateNumber}.` });
      return;
    }
    try {
      const assignment = await prisma.driverVehicleAssignment.create({
        data: { driverId: driver.id, vehicleId: vehicle.id, assignedById: req.staff!.id },
      });
      await writeAudit({
        actorType: 'admin',
        actorId: req.staff!.id,
        action: 'VEHICLE_ASSIGNED',
        targetType: 'driver',
        targetId: driver.id,
        details: { vehicleId: vehicle.id, plateNumber: vehicle.plateNumber },
      });
      res.status(201).json({ assignment: { id: assignment.id, driverId: driver.id, vehicleId: vehicle.id } });
    } catch (err) {
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
        res.status(409).json({ error: 'That assignment already exists.' });
        return;
      }
      throw err;
    }
  } catch (err) {
    next(err);
  }
});

router.delete('/assignments/:id', async (req, res, next) => {
  try {
    if (!can(req, FLEET_WRITERS)) return deny(res);
    const assignment = await prisma.driverVehicleAssignment.findFirst({ where: { id: idParam(req), revokedAt: null } });
    if (!assignment || !(await scopedDriver(req, assignment.driverId))) {
      res.status(404).json({ error: 'Assignment not found.' });
      return;
    }
    // Never pull a jeepney out from under a trip in progress.
    const inUse = await prisma.trip.findFirst({
      where: { driverId: assignment.driverId, vehicleId: assignment.vehicleId, status: 'ACTIVE' },
      select: { id: true },
    });
    if (inUse) {
      res.status(409).json({ error: 'The driver is on an active trip with this jeepney. Remove the assignment after the trip ends.' });
      return;
    }
    // Revoked, not deleted — past trips keep pointing at the vehicle.
    await prisma.driverVehicleAssignment.update({
      where: { id: assignment.id },
      data: { revokedAt: new Date(), revokedById: req.staff!.id },
    });
    await writeAudit({
      actorType: 'admin',
      actorId: req.staff!.id,
      action: 'VEHICLE_UNASSIGNED',
      targetType: 'driver',
      targetId: assignment.driverId,
      details: { vehicleId: assignment.vehicleId },
    });
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// TRIPS & OCCUPANCY
// ---------------------------------------------------------------------------
async function passengerStats(tripIds: string[]) {
  if (tripIds.length === 0) return new Map<string, { appServed: number; manualServed: number }>();
  const [app, manual] = await Promise.all([
    prisma.$queryRaw<{ tripId: string; served: bigint }[]>`
      SELECT "tripId", COALESCE(SUM(COALESCE("riders", 1)), 0) AS served
      FROM "TripBoarding" WHERE "tripId" IN (${Prisma.join(tripIds)}) AND "status" <> 'CANCELLED' GROUP BY "tripId"`,
    prisma.$queryRaw<{ tripId: string; served: bigint }[]>`
      SELECT "tripId",
             COALESCE(SUM(CASE WHEN "delta" = 1 AND "undoOfId" IS NULL THEN 1
                               WHEN "delta" = -1 AND "undoOfId" IS NOT NULL THEN -1 ELSE 0 END), 0) AS served
      FROM "ManualPassengerAdjustment" WHERE "tripId" IN (${Prisma.join(tripIds)}) GROUP BY "tripId"`,
  ]);
  const out = new Map<string, { appServed: number; manualServed: number }>();
  for (const id of tripIds) out.set(id, { appServed: 0, manualServed: 0 });
  for (const r of app) out.get(r.tripId)!.appServed = Number(r.served);
  for (const r of manual) out.get(r.tripId)!.manualServed = Number(r.served);
  return out;
}

async function tripScope(req: Request): Promise<Prisma.TripWhereInput> {
  if (!isOperator(req)) return {};
  const ids = (await visibleDriverIds(req)) ?? [];
  return { OR: [{ driverId: { in: ids } }, { vehicle: { operatorId: req.staff!.id } }] };
}

router.get('/trips', async (req, res, next) => {
  try {
    const q = pageSchema.extend({
      status: z.enum(['ACTIVE', 'COMPLETED']).optional(),
      from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      driverId: z.string().optional(),
      vehicleId: z.string().optional(),
    }).parse(req.query);

    const where: Prisma.TripWhereInput = {
      AND: [
        await tripScope(req),
        {
          ...(q.status ? { status: q.status } : {}),
          ...(q.driverId ? { driverId: q.driverId } : {}),
          ...(q.vehicleId ? { vehicleId: q.vehicleId } : {}),
          ...(q.from || q.to
            ? {
                startedAt: {
                  ...(q.from ? { gte: manilaMidnight(q.from) } : {}),
                  ...(q.to ? { lt: new Date(manilaMidnight(q.to).getTime() + 86_400_000) } : {}),
                },
              }
            : {}),
        },
      ],
    };
    const [trips, total] = await Promise.all([
      prisma.trip.findMany({ where, orderBy: { startedAt: 'desc' }, skip: (q.page - 1) * q.pageSize, take: q.pageSize, include: { vehicle: true } }),
      prisma.trip.count({ where }),
    ]);
    const drivers = await prisma.driver.findMany({ where: { id: { in: [...new Set(trips.map((t) => t.driverId))] } }, select: { id: true, fullName: true } });
    const driverName = new Map(drivers.map((d) => [d.id, d.fullName]));
    const stats = await passengerStats(trips.map((t) => t.id));
    const live = new Map<string, Awaited<ReturnType<typeof getOccupancy>>>();
    await Promise.all(trips.filter((t) => t.status === 'ACTIVE').map(async (t) => live.set(t.id, await getOccupancy(prisma, t.id))));

    res.json({
      trips: trips.map((t) => {
        const s = stats.get(t.id)!;
        const occ = live.get(t.id) ?? null;
        return {
          id: t.id,
          driverId: t.driverId,
          driverName: driverName.get(t.driverId) ?? 'Unknown',
          vehicleId: t.vehicleId,
          plateNumber: t.vehicle?.plateNumber ?? t.plateNumber,
          route: t.route,
          status: t.status,
          startedAt: t.startedAt,
          endedAt: t.endedAt,
          seatingCapacity: t.vehicle?.seatingCapacity ?? t.capacitySnapshot,
          // Live for active trips; for finished ones, how many were carried.
          appPassengers: occ ? occ.appPassengers : s.appServed,
          manualPassengers: occ ? occ.manualPassengers : s.manualServed,
          totalPassengers: occ ? occ.totalPassengers : s.appServed + s.manualServed,
          peakOccupancy: t.peakOccupancy,
          occupancyStatus: occ?.status ?? null,
          remainingSeats: occ?.remainingSeats ?? null,
          isShortTrip: t.isShortTrip,
        };
      }),
      currentPage: q.page,
      pageSize: q.pageSize,
      totalTrips: total,
      totalPages: Math.max(1, Math.ceil(total / q.pageSize)),
    });
  } catch (err) {
    next(err);
  }
});

router.get('/trips/:id', async (req, res, next) => {
  try {
    const trip = await prisma.trip.findFirst({ where: { AND: [{ id: idParam(req) }, await tripScope(req)] }, include: { vehicle: true } });
    if (!trip) {
      res.status(404).json({ error: 'Trip not found.' });
      return;
    }
    const [driver, adjustments, boardings, occupancy] = await Promise.all([
      prisma.driver.findUnique({ where: { id: trip.driverId }, select: { fullName: true, driverId: true } }),
      prisma.manualPassengerAdjustment.findMany({ where: { tripId: trip.id }, orderBy: { createdAt: 'asc' } }),
      prisma.tripBoarding.findMany({ where: { tripId: trip.id }, orderBy: { boardedAt: 'asc' }, select: { id: true, boardedAt: true, alightedAt: true, status: true, riders: true } }),
      getOccupancy(prisma, trip.id),
    ]);
    res.json({
      trip: {
        id: trip.id,
        driverName: driver?.fullName ?? 'Unknown',
        plateNumber: trip.vehicle?.plateNumber ?? trip.plateNumber,
        route: trip.route,
        status: trip.status,
        startedAt: trip.startedAt,
        endedAt: trip.endedAt,
        peakOccupancy: trip.peakOccupancy,
        capacitySnapshot: trip.capacitySnapshot,
      },
      occupancy,
      manualAdjustments: adjustments,
      appBoardings: boardings,
    });
  } catch (err) {
    next(err);
  }
});

router.get('/overview', async (req, res, next) => {
  try {
    const driverIds = await visibleDriverIds(req);
    const tScope = await tripScope(req);
    const driverWhere = driverScope(req);
    const [drivers, vehicles, activeTrips, completedToday, pendingIncidents, activeRestrictions, missingCapacity] = await Promise.all([
      prisma.driver.count({ where: driverWhere }),
      prisma.vehicle.count({ where: { ...vehicleScope(req), isActive: true } }),
      prisma.trip.findMany({ where: { AND: [tScope, { status: 'ACTIVE' }] }, select: { id: true } }),
      prisma.trip.count({ where: { AND: [tScope, { status: 'COMPLETED', startedAt: { gte: manilaMidnight(manilaDayKey(new Date())) } }] } }),
      prisma.shortTripIncident.count({ where: { status: { in: ['PENDING_EXPLANATION', 'EXPLAINED', 'UNDER_REVIEW'] }, ...(driverIds ? { driverId: { in: driverIds } } : {}) } }),
      prisma.driverRestriction.count({
        where: { liftedAt: null, expiresAt: { gt: new Date() }, ...(driverIds ? { driverId: { in: driverIds } } : {}) },
      }),
      prisma.vehicle.count({ where: { ...vehicleScope(req), isActive: true, seatingCapacity: null } }),
    ]);
    const occs = await Promise.all(activeTrips.map((t) => getOccupancy(prisma, t.id)));
    res.json({
      drivers,
      vehicles,
      vehiclesMissingCapacity: missingCapacity,
      activeTrips: activeTrips.length,
      completedTripsToday: completedToday,
      jeepneysNearlyFull: occs.filter((o) => o?.status === 'NEARLY_FULL').length,
      jeepneysFull: occs.filter((o) => o?.status === 'FULL').length,
      passengersOnBoard: occs.reduce((n, o) => n + (o?.totalPassengers ?? 0), 0),
      openIncidents: pendingIncidents,
      activeRestrictions,
      role: req.staff!.role,
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// SHORT-TRIPPING INCIDENTS
// ---------------------------------------------------------------------------
async function incidentWhere(req: Request, extra: Prisma.ShortTripIncidentWhereInput = {}): Promise<Prisma.ShortTripIncidentWhereInput> {
  const ids = await visibleDriverIds(req);
  return { ...(ids ? { driverId: { in: ids } } : {}), ...extra };
}

async function incidentViews(incidents: Prisma.ShortTripIncidentGetPayload<object>[]) {
  const drivers = await prisma.driver.findMany({
    where: { id: { in: [...new Set(incidents.map((i) => i.driverId))] } },
    select: { id: true, fullName: true, driverId: true },
  });
  const vehicles = await prisma.vehicle.findMany({
    where: { id: { in: [...new Set(incidents.map((i) => i.vehicleId).filter((x): x is string => !!x))] } },
    select: { id: true, plateNumber: true },
  });
  const dn = new Map(drivers.map((d) => [d.id, d]));
  const vp = new Map(vehicles.map((v) => [v.id, v.plateNumber]));
  return incidents.map((i) => ({
    ...i,
    driverName: dn.get(i.driverId)?.fullName ?? 'Unknown',
    driverCode: dn.get(i.driverId)?.driverId ?? null,
    plateNumber: i.vehicleId ? vp.get(i.vehicleId) ?? null : null,
    countedInRestriction: i.restrictionId !== null,
  }));
}

router.get('/incidents', async (req, res, next) => {
  try {
    const q = pageSchema.extend({
      status: z.enum(['PENDING_EXPLANATION', 'EXPLAINED', 'UNDER_REVIEW', 'CONFIRMED', 'DISMISSED', 'DUPLICATE']).optional(),
      open: z.enum(['1']).optional(),
      driverId: z.string().optional(),
    }).parse(req.query);
    const where = await incidentWhere(req, {
      ...(q.status ? { status: q.status } : {}),
      ...(q.open ? { status: { in: ['PENDING_EXPLANATION', 'EXPLAINED', 'UNDER_REVIEW'] } } : {}),
      ...(q.driverId ? { driverId: q.driverId } : {}),
    });
    const [incidents, total] = await Promise.all([
      prisma.shortTripIncident.findMany({ where, orderBy: { occurredAt: 'desc' }, skip: (q.page - 1) * q.pageSize, take: q.pageSize }),
      prisma.shortTripIncident.count({ where }),
    ]);
    res.json({
      incidents: await incidentViews(incidents),
      currentPage: q.page,
      pageSize: q.pageSize,
      totalIncidents: total,
      totalPages: Math.max(1, Math.ceil(total / q.pageSize)),
    });
  } catch (err) {
    next(err);
  }
});

// A reviewer recording an incident they observed/received outside the app.
const createIncidentSchema = z.object({
  driverId: z.string().trim().min(1),
  tripId: z.string().trim().min(1).optional(),
  route: z.string().trim().max(200).optional(),
  intendedDestination: z.string().trim().max(200).optional(),
  occurredAt: z.coerce.date().optional(),
  description: z.string().trim().min(3).max(2000),
});

router.post('/incidents', async (req, res, next) => {
  try {
    if (!can(req, FLEET_WRITERS)) return deny(res);
    const body = createIncidentSchema.parse(req.body);
    const driver = await scopedDriver(req, body.driverId);
    if (!driver) {
      res.status(404).json({ error: 'Driver not found.' });
      return;
    }
    const trip = body.tripId ? await prisma.trip.findFirst({ where: { id: body.tripId, driverId: driver.id } }) : null;
    if (body.tripId && !trip) {
      res.status(404).json({ error: 'That trip does not belong to this driver.' });
      return;
    }
    const incident = await prisma.$transaction(async (tx) => {
      const created = await tx.shortTripIncident.create({
        data: {
          driverId: driver.id,
          tripId: trip?.id ?? null,
          vehicleId: trip?.vehicleId ?? null,
          route: body.route ?? trip?.route ?? null,
          intendedDestination: body.intendedDestination ?? null,
          source: 'OPERATOR_REPORT',
          occurredAt: body.occurredAt ?? new Date(),
          description: body.description,
          createdById: req.staff!.id,
        },
      });
      await writeAudit({ actorType: 'admin', actorId: req.staff!.id, action: 'INCIDENT_CREATED', targetType: 'incident', targetId: created.id }, tx);
      await applyRestrictionIfNeeded(tx, driver.id, { type: 'admin', id: req.staff!.id });
      return created;
    });
    await notifyDriver({
      recipientId: driver.id,
      title: 'Explanation needed',
      message: 'A possible short-tripping incident was recorded. Please explain what happened.',
      type: 'SHORT_TRIP_INCIDENT',
      referenceId: incident.id,
    });
    res.status(201).json({ incident: (await incidentViews([incident]))[0] });
  } catch (err) {
    next(err);
  }
});

const reviewIncidentSchema = z.object({
  status: z.enum(['UNDER_REVIEW', 'CONFIRMED', 'DISMISSED', 'DUPLICATE']),
  note: z.string().trim().max(2000).optional(),
});

router.patch('/incidents/:id/review', async (req, res, next) => {
  try {
    if (!can(req, INCIDENT_REVIEWERS)) return deny(res);
    const body = reviewIncidentSchema.parse(req.body);
    const incident = await prisma.shortTripIncident.findFirst({ where: await incidentWhere(req, { id: idParam(req) }) });
    if (!incident) {
      res.status(404).json({ error: 'Incident not found.' });
      return;
    }
    if (body.status !== 'UNDER_REVIEW' && !body.note?.trim()) {
      res.status(400).json({ error: 'Please record the reason for this decision.' });
      return;
    }
    const { shortTripCountOnlyConfirmed } = await getSettings();

    const result = await prisma.$transaction(async (tx) => {
      const updated = await tx.shortTripIncident.update({
        where: { id: incident.id },
        data: { status: body.status, reviewNote: body.note ?? incident.reviewNote, reviewedById: req.staff!.id, reviewedAt: new Date() },
      });
      // A correction: this incident was already counted toward a restriction
      // but no longer qualifies — release it (and lift the restriction if it
      // no longer has enough behind it).
      const stillCounts = body.status === 'CONFIRMED' || (!shortTripCountOnlyConfirmed && body.status === 'UNDER_REVIEW');
      if (!stillCounts && incident.restrictionId) {
        await releaseIncidentFromRestriction(tx, incident, req.staff!.id);
      }
      await writeAudit(
        {
          actorType: 'admin',
          actorId: req.staff!.id,
          action: 'INCIDENT_REVIEWED',
          targetType: 'incident',
          targetId: incident.id,
          details: { from: incident.status, to: body.status, note: body.note ?? null },
        },
        tx,
      );
      const restriction = stillCounts ? await applyRestrictionIfNeeded(tx, incident.driverId, { type: 'admin', id: req.staff!.id }) : null;
      return { updated, restriction };
    });

    if (body.status === 'CONFIRMED' || body.status === 'DISMISSED') {
      await notifyDriver({
        recipientId: incident.driverId,
        title: body.status === 'CONFIRMED' ? 'Short-tripping incident confirmed' : 'Short-tripping report dismissed',
        message: body.note ?? '',
        type: 'SHORT_TRIP_INCIDENT',
        referenceId: incident.id,
      });
    }
    if (result.restriction) {
      await notifyDriver({
        recipientId: incident.driverId,
        title: 'Trip-start restriction applied',
        message: `You cannot start a new trip until ${result.restriction.expiresAt.toISOString()}.`,
        type: 'DRIVER_RESTRICTION',
        referenceId: result.restriction.id,
      });
    }
    res.json({
      incident: (await incidentViews([result.updated]))[0],
      restrictionApplied: result.restriction ? toPublicRestriction(result.restriction) : null,
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// RESTRICTIONS
// ---------------------------------------------------------------------------
router.get('/restrictions', async (req, res, next) => {
  try {
    const q = pageSchema.extend({ active: z.enum(['1']).optional(), driverId: z.string().optional() }).parse(req.query);
    const ids = await visibleDriverIds(req);
    const now = new Date();
    const where: Prisma.DriverRestrictionWhereInput = {
      ...(ids ? { driverId: { in: ids } } : {}),
      ...(q.driverId ? { driverId: q.driverId } : {}),
      ...(q.active ? { liftedAt: null, expiresAt: { gt: now } } : {}),
    };
    const [rows, total] = await Promise.all([
      prisma.driverRestriction.findMany({ where, orderBy: { createdAt: 'desc' }, skip: (q.page - 1) * q.pageSize, take: q.pageSize }),
      prisma.driverRestriction.count({ where }),
    ]);
    const drivers = await prisma.driver.findMany({ where: { id: { in: [...new Set(rows.map((r) => r.driverId))] } }, select: { id: true, fullName: true } });
    const dn = new Map(drivers.map((d) => [d.id, d.fullName]));
    const admins = await prisma.admin.findMany({
      where: { id: { in: [...new Set(rows.flatMap((r) => [r.appliedById, r.liftedById]).filter((x): x is string => !!x))] } },
      select: { id: true, fullName: true },
    });
    const an = new Map(admins.map((a) => [a.id, a.fullName]));
    res.json({
      restrictions: rows.map((r) => ({
        ...r,
        driverName: dn.get(r.driverId) ?? 'Unknown',
        appliedByName: r.appliedById ? an.get(r.appliedById) ?? null : 'System',
        liftedByName: r.liftedById ? an.get(r.liftedById) ?? null : null,
        state: r.liftedAt ? 'LIFTED' : r.expiresAt > now ? 'ACTIVE' : 'EXPIRED',
      })),
      currentPage: q.page,
      pageSize: q.pageSize,
      totalRestrictions: total,
      totalPages: Math.max(1, Math.ceil(total / q.pageSize)),
    });
  } catch (err) {
    next(err);
  }
});

router.post('/restrictions', async (req, res, next) => {
  try {
    // Manual application is administrator-only; operators/MANIBELA reach a
    // restriction through confirming incidents.
    if (!can(req, SETTINGS_WRITERS)) return deny(res);
    const body = z
      .object({
        driverId: z.string().trim().min(1),
        durationMinutes: z.number().int().min(1).max(10080),
        reason: z.string().trim().min(3).max(1000),
      })
      .parse(req.body);
    const driver = await prisma.driver.findUnique({ where: { id: body.driverId } });
    if (!driver) {
      res.status(404).json({ error: 'Driver not found.' });
      return;
    }
    const startsAt = new Date();
    const restriction = await prisma.driverRestriction.create({
      data: {
        driverId: driver.id,
        reason: body.reason,
        startsAt,
        expiresAt: new Date(startsAt.getTime() + body.durationMinutes * 60_000),
        durationMinutes: body.durationMinutes,
        appliedById: req.staff!.id,
      },
    });
    await writeAudit({
      actorType: 'admin',
      actorId: req.staff!.id,
      action: 'RESTRICTION_APPLIED_MANUALLY',
      targetType: 'driver',
      targetId: driver.id,
      details: { restrictionId: restriction.id, durationMinutes: body.durationMinutes, reason: body.reason },
    });
    res.status(201).json({ restriction: toPublicRestriction(restriction) });
  } catch (err) {
    next(err);
  }
});

router.post('/restrictions/:id/lift', async (req, res, next) => {
  try {
    if (!can(req, FLEET_WRITERS)) return deny(res);
    const body = z.object({ note: z.string().trim().min(3).max(1000) }).parse(req.body);
    const restriction = await prisma.driverRestriction.findUnique({ where: { id: idParam(req) } });
    if (!restriction || !(await scopedDriver(req, restriction.driverId))) {
      res.status(404).json({ error: 'Restriction not found.' });
      return;
    }
    if (restriction.liftedAt) {
      res.status(409).json({ error: 'This restriction was already lifted.' });
      return;
    }
    await prisma.driverRestriction.update({
      where: { id: restriction.id },
      data: { liftedAt: new Date(), liftedById: req.staff!.id, liftNote: body.note },
    });
    await writeAudit({
      actorType: 'admin',
      actorId: req.staff!.id,
      action: 'RESTRICTION_LIFTED',
      targetType: 'driver',
      targetId: restriction.driverId,
      details: { restrictionId: restriction.id, note: body.note },
    });
    await notifyDriver({
      recipientId: restriction.driverId,
      title: 'Trip-start restriction lifted',
      message: 'You can start trips again.',
      type: 'DRIVER_RESTRICTION',
      referenceId: restriction.id,
    });
    res.json({ ok: true, stillActive: !!(await getActiveRestriction(restriction.driverId)) });
  } catch (err) {
    next(err);
  }
});

router.get('/audit', async (req, res, next) => {
  try {
    if (isOperator(req)) return deny(res);
    const q = z.object({ targetType: z.string().optional(), targetId: z.string().optional() }).parse(req.query);
    const rows = await prisma.auditLog.findMany({
      where: { ...(q.targetType ? { targetType: q.targetType } : {}), ...(q.targetId ? { targetId: q.targetId } : {}) },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    res.json({ entries: rows });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// REPORTS — daily / monthly operations with passenger counts and the three
// kinds of earnings kept apart:
//   driverReported : what the driver typed into their Daily Operations log
//   estimated      : passengers x a configured fare. Only an estimate, and
//                    null unless admins configure a fare — it is NOT income
//   verified       : confirmed by an authorized reviewer against the actual
//                    collection/remittance
// ---------------------------------------------------------------------------
const reportQuery = z.object({
  period: z.enum(['day', 'month']).default('day'),
  // YYYY-MM-DD for day, YYYY-MM for month
  date: z.string().regex(/^\d{4}-\d{2}(-\d{2})?$/).optional(),
});

function reportRange(period: 'day' | 'month', date?: string) {
  const today = manilaDayKey(new Date());
  if (period === 'day') {
    const day = date && date.length === 10 ? date : today;
    const start = manilaMidnight(day);
    return { label: day, start, end: new Date(start.getTime() + 86_400_000), days: [day] };
  }
  const month = date ? date.slice(0, 7) : today.slice(0, 7);
  const start = manilaMidnight(`${month}-01`);
  const [y, m] = month.split('-').map(Number);
  const next = m === 12 ? `${y + 1}-01` : `${y}-${String(m + 1).padStart(2, '0')}`;
  const end = manilaMidnight(`${next}-01`);
  const days: string[] = [];
  for (let t = start.getTime(); t < end.getTime(); t += 86_400_000) days.push(manilaDayKey(new Date(t)));
  return { label: month, start, end, days };
}

router.get('/reports', async (req, res, next) => {
  try {
    const q = reportQuery.parse(req.query);
    const range = reportRange(q.period, q.date);
    const settings = await getSettings();
    const fare = settings.estimatedFarePerPassenger as number | null;

    const trips = await prisma.trip.findMany({
      where: { AND: [await tripScope(req), { startedAt: { gte: range.start, lt: range.end } }] },
      orderBy: { startedAt: 'asc' },
      include: { vehicle: true },
    });
    const stats = await passengerStats(trips.map((t) => t.id));
    const driverIds = [...new Set(trips.map((t) => t.driverId))];
    const scopeIds = await visibleDriverIds(req);
    const reportDriverIds = scopeIds ?? (await prisma.driver.findMany({ select: { id: true } })).map((d) => d.id);
    const drivers = await prisma.driver.findMany({ where: { id: { in: reportDriverIds } }, select: { id: true, fullName: true, driverId: true } });
    const dn = new Map(drivers.map((d) => [d.id, d]));

    const tripRows = trips.map((t) => {
      const s = stats.get(t.id)!;
      return {
        id: t.id,
        date: manilaDayKey(t.startedAt),
        driverId: t.driverId,
        driverName: dn.get(t.driverId)?.fullName ?? 'Unknown',
        plateNumber: t.vehicle?.plateNumber ?? t.plateNumber,
        route: t.route,
        status: t.status,
        startedAt: t.startedAt,
        endedAt: t.endedAt,
        seatingCapacity: t.vehicle?.seatingCapacity ?? t.capacitySnapshot,
        appPassengers: s.appServed,
        manualPassengers: s.manualServed,
        totalPassengers: s.appServed + s.manualServed,
        peakOccupancy: t.peakOccupancy,
      };
    });

    // Earnings — one log per driver per day; scoped drivers only.
    const logs = await prisma.driverDailyLog.findMany({
      where: {
        driverId: { in: reportDriverIds },
        date: { gte: new Date(`${range.days[0]}T00:00:00Z`), lte: new Date(`${range.days[range.days.length - 1]}T00:00:00Z`) },
      },
      orderBy: { date: 'asc' },
    });

    const perDriver = new Map<
      string,
      { driverId: string; driverName: string; trips: number; completedTrips: number; appPassengers: number; manualPassengers: number; daysOperated: Set<string> }
    >();
    for (const r of tripRows) {
      const e = perDriver.get(r.driverId) ?? {
        driverId: r.driverId,
        driverName: r.driverName,
        trips: 0,
        completedTrips: 0,
        appPassengers: 0,
        manualPassengers: 0,
        daysOperated: new Set<string>(),
      };
      e.trips += 1;
      if (r.status === 'COMPLETED') e.completedTrips += 1;
      e.appPassengers += r.appPassengers;
      e.manualPassengers += r.manualPassengers;
      e.daysOperated.add(r.date);
      perDriver.set(r.driverId, e);
    }

    const nonOp = await prisma.driverNonOperationDay.findMany({
      where: { driverId: { in: reportDriverIds }, date: { gte: new Date(`${range.days[0]}T00:00:00Z`), lte: new Date(`${range.days[range.days.length - 1]}T00:00:00Z`) } },
    });

    const incidents = await prisma.shortTripIncident.count({
      where: { driverId: { in: reportDriverIds }, occurredAt: { gte: range.start, lt: range.end } },
    });
    const complaints = await prisma.complaint.count({
      where: { driverId: { in: reportDriverIds }, createdAt: { gte: range.start, lt: range.end } },
    });

    const totalPassengers = tripRows.reduce((n, r) => n + r.totalPassengers, 0);
    const driverReported = logs.reduce((n, l) => n + l.earnings, 0);
    const verifiedLogs = logs.filter((l) => l.verifiedEarnings !== null);

    res.json({
      period: q.period,
      label: range.label,
      totals: {
        trips: tripRows.length,
        completedTrips: tripRows.filter((r) => r.status === 'COMPLETED').length,
        activeTrips: tripRows.filter((r) => r.status === 'ACTIVE').length,
        appPassengers: tripRows.reduce((n, r) => n + r.appPassengers, 0),
        manualPassengers: tripRows.reduce((n, r) => n + r.manualPassengers, 0),
        totalPassengers,
        incidents,
        complaints,
      },
      earnings: {
        driverReported,
        driverReportedLogs: logs.length,
        // Never presented as income — only a passenger-count x configured fare.
        estimated: fare === null ? null : Math.round(totalPassengers * fare * 100) / 100,
        estimatedFare: fare,
        verified: verifiedLogs.length ? verifiedLogs.reduce((n, l) => n + (l.verifiedEarnings ?? 0), 0) : null,
        verifiedLogs: verifiedLogs.length,
        unverifiedLogs: logs.length - verifiedLogs.length,
      },
      drivers: [...perDriver.values()].map((d) => ({
        ...d,
        daysOperated: d.daysOperated.size,
        daysInPeriod: range.days.length,
      })),
      driversNotOperating: reportDriverIds
        .filter((id) => !perDriver.has(id))
        .map((id) => ({
          driverId: id,
          driverName: dn.get(id)?.fullName ?? 'Unknown',
          reasons: nonOp.filter((n) => n.driverId === id).map((n) => ({ date: formatDateOnly(n.date), reason: n.reason })),
        })),
      trips: tripRows,
      earningsLogs: logs.map((l) => ({
        id: l.id,
        date: formatDateOnly(l.date),
        driverId: l.driverId,
        driverName: dn.get(l.driverId)?.fullName ?? 'Unknown',
        driverReported: l.earnings,
        verified: l.verifiedEarnings,
        verificationNote: l.verificationNote,
      })),
    });
  } catch (err) {
    next(err);
  }
});

router.post('/earnings/:logId/verify', async (req, res, next) => {
  try {
    if (!can(req, FLEET_WRITERS)) return deny(res);
    const body = z.object({ verifiedEarnings: z.number().finite().min(0).max(10_000_000), note: z.string().trim().max(500).optional() }).parse(req.body);
    const log = await prisma.driverDailyLog.findUnique({ where: { id: idParam(req, 'logId') } });
    if (!log || !(await scopedDriver(req, log.driverId))) {
      res.status(404).json({ error: 'Earnings record not found.' });
      return;
    }
    await prisma.driverDailyLog.update({
      where: { id: log.id },
      data: { verifiedEarnings: body.verifiedEarnings, verifiedById: req.staff!.id, verifiedAt: new Date(), verificationNote: body.note ?? null },
    });
    await writeAudit({
      actorType: 'admin',
      actorId: req.staff!.id,
      action: 'EARNINGS_VERIFIED',
      targetType: 'daily-log',
      targetId: log.id,
      details: { driverReported: log.earnings, verified: body.verifiedEarnings },
    });
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

export default router;
