import { prisma } from './prisma';
import { notifyAdmin, notifyDriver } from '../utils/notify';
import { evaluateRestriction } from './restrictions';

/** The complaint type that opens a short-tripping incident. Matches the
 * option in the commuter app's complaint form. */
export const SHORT_TRIPPING_COMPLAINT_TYPE = 'Short-Tripping';

/**
 * Who was driving the jeepney with this plate? Preference order: the trip the
 * commuter named, the driver on that vehicle's ACTIVE trip, the driver of its
 * most recent trip, then — for plates with no trips yet — a driver assigned to
 * that vehicle (or, for pre-vehicle data, the legacy Driver.plateNumber).
 * A driver may have several jeepneys, so the plate alone says nothing about
 * the driver without this.
 */
export async function resolveDriverForPlate(plateNumber: string, tripId?: string | null) {
  if (tripId) {
    const trip = await prisma.trip.findUnique({ where: { id: tripId } });
    if (trip) {
      const driver = await prisma.driver.findUnique({ where: { id: trip.driverId } });
      if (driver) return { driver, trip, vehicleId: trip.vehicleId };
    }
  }
  const vehicle = await prisma.vehicle.findUnique({ where: { plateNumber } });
  if (vehicle) {
    const trip =
      (await prisma.trip.findFirst({ where: { vehicleId: vehicle.id, status: 'ACTIVE' } })) ??
      (await prisma.trip.findFirst({ where: { vehicleId: vehicle.id }, orderBy: { startedAt: 'desc' } }));
    if (trip) {
      const driver = await prisma.driver.findUnique({ where: { id: trip.driverId } });
      if (driver) return { driver, trip, vehicleId: vehicle.id };
    }
    const assignment = await prisma.driverVehicleAssignment.findFirst({
      where: { vehicleId: vehicle.id, revokedAt: null },
      orderBy: { assignedAt: 'desc' },
    });
    if (assignment) {
      const driver = await prisma.driver.findUnique({ where: { id: assignment.driverId } });
      if (driver) return { driver, trip: null, vehicleId: vehicle.id };
    }
  }
  const legacy = await prisma.driver.findFirst({ where: { plateNumber } });
  return legacy ? { driver: legacy, trip: null, vehicleId: vehicle?.id ?? null } : null;
}

/** Opens a PENDING_EXPLANATION incident for a short-tripping complaint and
 * asks the driver to explain. It does NOT count toward any restriction until a
 * reviewer confirms it. */
export async function openIncidentFromComplaint(complaint: {
  id: string;
  driverId: string;
  tripId: string | null;
  description: string;
  createdAt: Date;
}) {
  const trip = complaint.tripId ? await prisma.trip.findUnique({ where: { id: complaint.tripId } }) : null;
  const incident = await prisma.shortTripIncident.create({
    data: {
      tripId: trip?.id ?? null,
      driverId: complaint.driverId,
      vehicleId: trip?.vehicleId ?? null,
      route: trip?.route ?? null,
      source: 'COMMUTER_COMPLAINT',
      complaintId: complaint.id,
      occurredAt: complaint.createdAt,
      lat: trip?.currentLat ?? null,
      lng: trip?.currentLng ?? null,
      description: complaint.description,
    },
  });
  // Only matters when the policy is set to count unreviewed reports.
  await evaluateRestriction(complaint.driverId, { type: 'system', id: null });
  await notifyDriver({
    recipientId: complaint.driverId,
    title: 'Explanation needed',
    message: 'A passenger reported being made to get off before their destination. Please explain what happened.',
    type: 'SHORT_TRIP_INCIDENT',
    referenceId: incident.id,
  });
  await notifyAdmin({
    title: 'Possible short-tripping reported',
    message: 'A commuter reported being dropped off early — needs review.',
    type: 'SHORT_TRIP_INCIDENT',
    referenceId: complaint.driverId,
  });
  return incident;
}
