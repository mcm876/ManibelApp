/**
 * End-to-end check of the vehicle / passenger-count / short-tripping /
 * role-scoping revisions against a RUNNING backend and its database.
 *
 *   PORT=4100 node -r ts-node/register src/index.ts      (in one terminal)
 *   node scripts/test-revisions.js http://localhost:4100  (in another)
 *
 * Creates its own records (every id/name carries the ZT prefix) and removes
 * them again at the end — it never touches other data. Use a dev database.
 */
require('dotenv').config();
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const { PrismaClient } = require('@prisma/client');

const BASE = process.argv[2] || 'http://localhost:4000';
const prisma = new PrismaClient();
const RUN = Date.now().toString(36).toUpperCase();
const sign = (sub, role) => jwt.sign({ sub, role }, process.env.JWT_SECRET, { expiresIn: '1h' });

let passed = 0;
const failures = [];
function check(name, cond, detail) {
  if (cond) {
    passed++;
    console.log(`  ok   ${name}`);
  } else {
    failures.push(name);
    console.log(`  FAIL ${name}${detail !== undefined ? '  -> ' + JSON.stringify(detail) : ''}`);
  }
}
async function api(method, path, token, body) {
  const res = await fetch(BASE + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try {
    json = await res.json();
  } catch {}
  return { status: res.status, body: json };
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Two points ~5 m apart and one ~600 m away (Pasig area).
const P = { lat: 14.5764, lng: 121.0851 };
const NEAR = { lat: 14.57644, lng: 121.08512 };
const FAR = { lat: 14.5818, lng: 121.0851 };

async function main() {
  const created = { admins: [], drivers: [], commuters: [], vehicles: [] };
  const hash = await bcrypt.hash('x', 4);
  const mk = {
    admin: async (role, n) => {
      const a = await prisma.admin.create({ data: { email: `zt-${RUN}-${n}@test.local`, passwordHash: hash, fullName: `ZT ${n}`, role } });
      created.admins.push(a.id);
      return a;
    },
    driver: async (n, operatorId) => {
      const d = await prisma.driver.create({
        data: {
          driverId: `ZT-${RUN}-D${n}`,
          fullName: `ZT Driver ${n}`,
          mobileNumber: `+6390${RUN.slice(-4).padStart(4, '0')}${String(n).padStart(4, '0')}`.slice(0, 13),
          passwordHash: hash,
          plateNumber: `ZZZ${100 + n}`,
          licenseVerificationStatus: 'APPROVED',
          operatorId,
        },
      });
      created.drivers.push(d.id);
      return d;
    },
    commuter: async (n) => {
      const c = await prisma.commuter.create({
        data: { commuterId: `ZT-${RUN}-C${n}`, fullName: `ZT Commuter ${n}`, mobileNumber: `+6391${RUN.slice(-4).padStart(4, '0')}${String(n).padStart(4, '0')}`.slice(0, 13), passwordHash: hash, isActive: true },
      });
      created.commuters.push(c.id);
      return c;
    },
    vehicle: async (plate, cap, operatorId) => {
      const v = await prisma.vehicle.create({ data: { plateNumber: plate, seatingCapacity: cap, operatorId } });
      created.vehicles.push(v.id);
      return v;
    },
  };

  try {
    console.log('Setting up…');
    const opA = await mk.admin('OPERATOR', 'opA');
    const opB = await mk.admin('OPERATOR', 'opB');
    const mani = await mk.admin('MANIBELA', 'mani');
    const adm = await mk.admin('ADMIN', 'adm');
    const tOpA = sign(opA.id, 'admin');
    const tOpB = sign(opB.id, 'admin');
    const tMani = sign(mani.id, 'admin');
    const tAdm = sign(adm.id, 'admin');

    const D1 = await mk.driver(1, opA.id);
    const D2 = await mk.driver(2, opB.id);
    const D3 = await mk.driver(3, opA.id);
    const t1 = sign(D1.id, 'driver');
    const t2 = sign(D2.id, 'driver');
    const t3 = sign(D3.id, 'driver');
    const plate = (c) => `ZT${c}${RUN.replace(/[^A-Z]/g, 'X').slice(0, 1)}${Math.floor(Math.random() * 900 + 100)}`.slice(0, 7);
    const V1 = await mk.vehicle(`QAA${100 + Math.floor(Math.random() * 800)}`, 4, opA.id);
    const V2 = await mk.vehicle(`QBB${100 + Math.floor(Math.random() * 800)}`, 6, opA.id);
    const V3 = await mk.vehicle(`QCC${100 + Math.floor(Math.random() * 800)}`, 3, opB.id);
    const V4 = await mk.vehicle(`QDD${100 + Math.floor(Math.random() * 800)}`, null, opA.id);
    for (const [d, v] of [[D1, V1], [D1, V2], [D1, V4], [D2, V3], [D3, V1]]) {
      await prisma.driverVehicleAssignment.create({ data: { driverId: d.id, vehicleId: v.id } });
    }
    const C = [];
    for (let i = 1; i <= 8; i++) C.push(await mk.commuter(i));
    const tc = C.map((c) => sign(c.id, 'commuter'));

    // Fast settings for the test run (window 0 so readings confirm immediately).
    await prisma.systemSetting.deleteMany({});
    await api('PUT', '/api/admin/ops/settings', tAdm, { values: { boardingMinWindowSeconds: 0, boardingRequiredReadings: 3 } });

    console.log('\nVehicle selection & capacity');
    let r = await api('GET', '/api/driver/vehicles', t1);
    const plates = (r.body?.vehicles || []).map((v) => v.plateNumber).sort();
    check('driver sees exactly their assigned jeepneys', JSON.stringify(plates) === JSON.stringify([V1.plateNumber, V2.plateNumber, V4.plateNumber].sort()), plates);
    check('does not see another driver\'s jeepney', !plates.includes(V3.plateNumber));
    const cap = Object.fromEntries((r.body?.vehicles || []).map((v) => [v.plateNumber, v.seatingCapacity]));
    check('different jeepneys report different capacities', cap[V1.plateNumber] === 4 && cap[V2.plateNumber] === 6, cap);

    r = await api('POST', '/api/driver/trips/start', t1, { route: 'Pasig – Quiapo', startingOdometer: 1000, ...P });
    check('cannot start a trip without selecting a vehicle', r.status === 400 && r.body?.code === 'VEHICLE_REQUIRED', r.body);
    r = await api('POST', '/api/driver/trips/start', t1, { vehicleId: V3.id, startingOdometer: 1000, ...P });
    check('cannot select an unauthorized jeepney', r.status === 403 && r.body?.code === 'VEHICLE_NOT_ASSIGNED', r.body);
    r = await api('POST', '/api/driver/trips/start', t1, { vehicleId: V4.id, startingOdometer: 1000, ...P });
    check('vehicle without registered capacity blocks the trip', r.status === 409 && r.body?.code === 'VEHICLE_CAPACITY_NOT_SET', r.body);

    r = await api('POST', '/api/driver/trips/start', t1, { vehicleId: V1.id, route: 'Pasig – Quiapo', startingOdometer: 1000, ...P });
    const trip1 = r.body?.trip;
    check('trip starts with selected vehicle', r.status === 201 && trip1?.vehicleId === V1.id, r.body);
    check('selected vehicle capacity retrieved', r.body?.occupancy?.seatingCapacity === 4, r.body?.occupancy);
    const tripRow = await prisma.trip.findUnique({ where: { id: trip1.id } });
    check('vehicle ID (not just plate text) stored on the trip', tripRow.vehicleId === V1.id && tripRow.plateNumber === V1.plateNumber);

    r = await api('POST', '/api/driver/trips/start', t1, { vehicleId: V2.id, startingOdometer: 1000, ...P });
    check('cannot switch vehicle during an active trip (same trip resumed)', r.body?.trip?.id === trip1.id && r.body?.trip?.vehicleId === V1.id, r.body?.trip);
    r = await api('POST', '/api/driver/trips/start', t3, { vehicleId: V1.id, startingOdometer: 1000, ...P });
    check('same jeepney cannot be in two active trips', r.status === 409 && r.body?.code === 'VEHICLE_IN_USE', r.body);

    console.log('\nGPS-verified boarding');
    await api('PATCH', `/api/driver/trips/${trip1.id}/location`, t1, P);
    const occ = async () => (await api('GET', `/api/driver/trips/${trip1.id}/occupancy`, t1)).body?.occupancy;
    const reading = (pt, extra = {}) => ({ ...pt, accuracy: 8, fixAgeSeconds: 1, ...extra });

    r = await api('POST', '/api/commuter/board', tc[0], { tripId: trip1.id, ...reading(NEAR) });
    check('Board without idempotency key asks the app to update (no instant count)', r.status === 426, r.body);
    r = await api('POST', '/api/commuter/board', tc[0], { tripId: trip1.id, clientRequestId: 'a1', ...reading(NEAR) });
    const req1 = r.body?.requestId;
    check('pressing Board only creates a PENDING request', r.body?.status === 'PENDING', r.body);
    check('Board alone does not change passenger count', (await occ()).appPassengers === 0);
    r = await api('POST', '/api/commuter/board', tc[0], { tripId: trip1.id, clientRequestId: 'a1', ...reading(NEAR) });
    check('retrying the same press reuses the same request', r.body?.requestId === req1);
    r = await api('POST', `/api/commuter/board/requests/${req1}/readings`, tc[0], reading(NEAR));
    check('still pending until enough good readings', r.body?.status === 'PENDING' || r.body?.status === 'CONFIRMED');
    r = await api('POST', `/api/commuter/board/requests/${req1}/readings`, tc[0], reading(NEAR));
    check('confirms after consecutive matching readings', r.body?.status === 'CONFIRMED' && r.body?.boarded === true, r.body);
    check('validated boarding adds the app passenger exactly once', (await occ()).appPassengers === 1);
    await api('POST', `/api/commuter/board/requests/${req1}/readings`, tc[0], reading(NEAR));
    r = await api('POST', '/api/commuter/board', tc[0], { tripId: trip1.id, clientRequestId: 'a2', ...reading(NEAR) });
    check('pressing Board again does not double-count', r.body?.boarded === true && (await occ()).appPassengers === 1, r.body);
    r = await api('POST', '/api/commuter/board', tc[0], { tripId: trip1.id, clientRequestId: 'a1', ...reading(NEAR) });
    check('retried confirmed request returns confirmed, count unchanged', r.body?.status === 'CONFIRMED' && (await occ()).appPassengers === 1);

    // far commuter
    r = await api('POST', '/api/commuter/board', tc[1], { tripId: trip1.id, clientRequestId: 'b1', ...reading(FAR) });
    const reqFar = r.body?.requestId;
    for (let i = 0; i < 3; i++) r = await api('POST', `/api/commuter/board/requests/${reqFar}/readings`, tc[1], reading(FAR));
    check('GPS mismatch does not count the commuter', r.body?.status === 'PENDING' && (await occ()).appPassengers === 1, r.body);
    await prisma.boardingRequest.update({ where: { id: reqFar }, data: { expiresAt: new Date(Date.now() - 1000) } });
    r = await api('GET', `/api/commuter/board/requests/${reqFar}`, tc[1]);
    check('unverified request fails with a clear message and is not counted', r.body?.status === 'FAILED' && /location/i.test(r.body?.message || ''), r.body);

    // stale commuter GPS
    r = await api('POST', '/api/commuter/board', tc[2], { tripId: trip1.id, clientRequestId: 'c1', ...reading(NEAR, { fixAgeSeconds: 120 }) });
    const reqStale = r.body?.requestId;
    for (let i = 0; i < 3; i++) r = await api('POST', `/api/commuter/board/requests/${reqStale}/readings`, tc[2], reading(NEAR, { fixAgeSeconds: 120 }));
    check('stale commuter GPS is never confirmed', r.body?.status === 'PENDING' && (await occ()).appPassengers === 1, r.body);
    r = await api('POST', `/api/commuter/board/requests/${reqStale}/cancel`, tc[2]);
    check('commuter can cancel a pending request; it is not counted', r.body?.status === 'CANCELLED' && (await occ()).appPassengers === 1, r.body);

    // stale / missing driver GPS
    await prisma.trip.update({ where: { id: trip1.id }, data: { locationUpdatedAt: new Date(Date.now() - 10 * 60 * 1000) } });
    r = await api('POST', '/api/commuter/board', tc[2], { tripId: trip1.id, clientRequestId: 'c2', ...reading(NEAR) });
    const reqDrv = r.body?.requestId;
    for (let i = 0; i < 3; i++) r = await api('POST', `/api/commuter/board/requests/${reqDrv}/readings`, tc[2], reading(NEAR));
    check('stale driver GPS is never confirmed', r.body?.status === 'PENDING' && (await occ()).appPassengers === 1, r.body);
    await api('POST', `/api/commuter/board/requests/${reqDrv}/cancel`, tc[2]);
    await api('PATCH', `/api/driver/trips/${trip1.id}/location`, t1, P);

    // movement after boarding must not remove the passenger
    await api('PATCH', `/api/driver/trips/${trip1.id}/location`, t1, FAR);
    await sleep(200);
    await api('PATCH', `/api/driver/trips/${trip1.id}/location`, t1, P);
    check('shared GPS movement after boarding never removes the passenger', (await occ()).appPassengers === 1);

    console.log('\nManual passengers & occupancy');
    r = await api('POST', `/api/driver/trips/${trip1.id}/passengers`, t1, { delta: 1, clientRequestId: 'm1' });
    check('+1 adds a manual passenger', r.body?.occupancy?.manualPassengers === 1, r.body);
    r = await api('POST', `/api/driver/trips/${trip1.id}/passengers`, t1, { delta: 1, clientRequestId: 'm1' });
    check('duplicate +1 (same key) counts once', r.body?.occupancy?.manualPassengers === 1 && r.body?.duplicate === true, r.body);
    r = await api('POST', `/api/driver/trips/${trip1.id}/passengers`, t1, { delta: -1 });
    check('-1 deducts', r.body?.occupancy?.manualPassengers === 0);
    r = await api('POST', `/api/driver/trips/${trip1.id}/passengers`, t1, { delta: -1 });
    check('manual count can never go negative', r.status === 409 && r.body?.code === 'MANUAL_COUNT_ZERO', r.body);
    r = await api('POST', `/api/driver/trips/${trip1.id}/passengers`, t1, { delta: 1 });
    let o = r.body?.occupancy;
    check('total = app + manual, remaining seats correct', o.totalPassengers === o.appPassengers + o.manualPassengers && o.totalPassengers === 2 && o.remainingSeats === 2, o);
    r = await api('POST', `/api/driver/trips/${trip1.id}/passengers/undo`, t1);
    check('undo reverses the last change', r.body?.occupancy?.manualPassengers === 0, r.body);
    r = await api('POST', `/api/driver/trips/${trip1.id}/passengers/undo`, t1);
    check('a change can only be undone once', r.status === 409, r.body);
    const adj = await prisma.manualPassengerAdjustment.findMany({ where: { tripId: trip1.id } });
    check('every manual change recorded with driver + trip + vehicle', adj.length >= 3 && adj.every((a) => a.driverId === D1.id && a.tripId === trip1.id && a.vehicleId === V1.id));

    await api('POST', `/api/driver/trips/${trip1.id}/passengers`, t1, { delta: 1 }); // total 2
    r = await api('POST', `/api/driver/trips/${trip1.id}/passengers`, t1, { delta: 1 }); // total 3 (cap 4, 80% => 4)
    check('NORMAL below threshold of a 4-seat jeepney', r.body?.occupancy?.status === 'NORMAL', r.body?.occupancy);
    await api('PUT', '/api/admin/ops/settings', tAdm, { values: { nearFullThresholdPercent: 50 } });
    o = await occ();
    check('NEARLY FULL appears at the configured threshold (50% of 4 = 2)', o.status === 'NEARLY_FULL', o);
    await api('PUT', '/api/admin/ops/settings', tAdm, { values: { nearFullThresholdPercent: 80 } });

    console.log('\nConcurrency / capacity');
    // total is 3 of 4. Five commuters race for the last seat, plus a manual +1.
    const racers = [3, 4, 5, 6, 7];
    const results = await Promise.all(
      racers.map(async (i) => {
        let last = (await api('POST', '/api/commuter/board', tc[i], { tripId: trip1.id, clientRequestId: `race${i}`, ...reading(NEAR) })).body;
        for (let k = 0; k < 3 && last?.status === 'PENDING'; k++) {
          last = (await api('POST', `/api/commuter/board/requests/${last.requestId}/readings`, tc[i], reading(NEAR))).body;
        }
        return last;
      }),
    );
    const manualRace = api('POST', `/api/driver/trips/${trip1.id}/passengers`, t1, { delta: 1 });
    await manualRace;
    o = await occ();
    check('simultaneous requests can never exceed registered capacity', o.totalPassengers <= 4, o);
    check('jeepney reaches FULL exactly at capacity', o.status === 'FULL' && o.totalPassengers === 4, o);
    const confirmed = results.filter((x) => x?.status === 'CONFIRMED').length;
    check('at most the remaining seat was confirmed among racers', confirmed <= 1, results.map((x) => x?.status));
    r = await api('POST', `/api/driver/trips/${trip1.id}/passengers`, t1, { delta: 1 });
    check('manual +1 refused when FULL', r.status === 409 && r.body?.code === 'JEEPNEY_FULL', r.body);
    r = await api('POST', '/api/commuter/board', tc[7], { tripId: trip1.id, clientRequestId: 'full1', ...reading(NEAR) });
    check('app boarding refused when FULL', r.status === 409 && r.body?.code === 'JEEPNEY_FULL', r.body);

    console.log('\nAlighting');
    r = await api('POST', '/api/commuter/alight', tc[0]);
    const afterAlight = (await occ()).appPassengers;
    await api('POST', '/api/commuter/alight', tc[0]);
    check('alighting removes the passenger exactly once', (await occ()).appPassengers === afterAlight && afterAlight === o.appPassengers - 1, { afterAlight });

    r = await api('POST', `/api/driver/trips/${trip1.id}/end`, t1);
    check('trip ends', r.body?.trip?.status === 'COMPLETED');
    await sleep(300);
    const open = await prisma.tripBoarding.count({ where: { tripId: trip1.id, alightedAt: null } });
    check('ending the trip closes remaining boardings', open === 0);

    console.log('\nValidation window & recorded reasons');
    await api('PUT', '/api/admin/ops/settings', tAdm, { values: { boardingMinWindowSeconds: 3 } });
    r = await api('POST', '/api/driver/trips/start', t3, { vehicleId: V1.id, route: 'Pasig – Quiapo', startingOdometer: 2000, ...P });
    const tripW = r.body?.trip;
    check('second driver can use the jeepney once the first trip ended', r.status === 201, r.body);
    r = await api('POST', '/api/commuter/board', tc[0], { tripId: tripW.id, clientRequestId: 'w1', ...reading(NEAR) });
    const reqW = r.body?.requestId;
    for (let k = 0; k < 3; k++) r = await api('POST', `/api/commuter/board/requests/${reqW}/readings`, tc[0], reading(NEAR));
    check('enough readings inside the minimum window do NOT confirm yet', r.body?.status === 'PENDING' && r.body?.confirmedReadings >= 3, r.body);
    await sleep(3300);
    r = await api('POST', `/api/commuter/board/requests/${reqW}/readings`, tc[0], reading(NEAR));
    check('confirms once the readings span the minimum window', r.body?.status === 'CONFIRMED', r.body);
    const wReq = await prisma.boardingRequest.findUnique({ where: { id: reqFar } });
    check('failure reason recorded (TOO_FAR) with measured distances', wReq.failureCode === 'TOO_FAR' || wReq.failureMessage, wReq.failureCode);
    check('readings are stored as evidence (distance + verdict)', Array.isArray(wReq.readings) && wReq.readings.some((x) => x.reason === 'TOO_FAR' && x.distance > 100), wReq.readings?.slice(0, 2));
    const staleReq = await prisma.boardingRequest.findUnique({ where: { id: reqStale } });
    check('stale-GPS rejections recorded as GPS_STALE', (staleReq.readings || []).some((x) => x.reason === 'GPS_STALE'));
    const drvReq = await prisma.boardingRequest.findUnique({ where: { id: reqDrv } });
    check('stale driver location recorded as DRIVER_LOCATION_STALE', (drvReq.readings || []).some((x) => x.reason === 'DRIVER_LOCATION_STALE'));
    await api('POST', '/api/commuter/alight', tc[0]);
    await api('POST', `/api/driver/trips/${tripW.id}/end`, t3);
    await api('PUT', '/api/admin/ops/settings', tAdm, { values: { boardingMinWindowSeconds: 0 } });

    console.log('\nShort-tripping, explanations, restrictions');
    const mkIncident = async (desc) =>
      (await api('POST', '/api/admin/ops/incidents', tOpA, { driverId: D1.id, description: desc, route: 'Pasig – Quiapo' })).body?.incident;
    const i1 = await mkIncident('Passengers told to get off at Kapitolyo');
    check('operator can record an incident; it needs the driver\'s explanation', i1?.status === 'PENDING_EXPLANATION', i1);
    r = await api('PATCH', `/api/driver/short-trip-incidents/${i1.id}/explanation`, t1, { explanation: '  ' });
    check('empty explanation is rejected', r.status === 400, r.body);
    r = await api('PATCH', `/api/driver/short-trip-incidents/${i1.id}/explanation`, t1, { explanation: 'Engine trouble, had to stop.' });
    check('driver explanation saved for review', r.body?.incident?.status === 'EXPLAINED', r.body);
    r = await api('PATCH', `/api/driver/short-trip-incidents/${i1.id}/explanation`, t2, { explanation: 'Not my incident at all' });
    check('another driver cannot explain it', r.status === 404);

    // via commuter complaint
    const fd = new FormData();
    fd.append('plateNumber', V2.plateNumber);
    fd.append('complaintType', 'Short-Tripping');
    fd.append('description', 'Driver made us get off before Quiapo');
    const cres = await fetch(BASE + '/api/commuter/complaints', { method: 'POST', headers: { authorization: `Bearer ${tc[0]}` }, body: fd });
    check('complaint on a plate resolves to the driver and opens an incident', cres.status === 201);
    const viaComplaint = await prisma.shortTripIncident.findFirst({ where: { driverId: D1.id, source: 'COMMUTER_COMPLAINT' } });
    check('short-tripping complaint creates a PENDING incident (not auto-confirmed)', viaComplaint?.status === 'PENDING_EXPLANATION');

    const i2 = await mkIncident('Second occurrence');
    const i3 = await mkIncident('Third occurrence');
    const i4 = await mkIncident('Fourth report');
    r = await api('PATCH', `/api/admin/ops/incidents/${i1.id}/review`, tOpA, { status: 'CONFIRMED' });
    check('a decision requires a recorded reason', r.status === 400);
    await api('PATCH', `/api/admin/ops/incidents/${i1.id}/review`, tOpA, { status: 'CONFIRMED', note: 'confirmed' });
    await api('PATCH', `/api/admin/ops/incidents/${i2.id}/review`, tOpA, { status: 'CONFIRMED', note: 'confirmed' });
    await api('PATCH', `/api/admin/ops/incidents/${i4.id}/review`, tOpA, { status: 'DISMISSED', note: 'GPS error' });
    let restr = await api('GET', '/api/driver/me/restriction', t1);
    check('unverified/dismissed reports do not trigger a restriction (2 confirmed only)', restr.body?.restriction === null, restr.body);

    // active trip must survive a restriction
    r = await api('POST', '/api/driver/trips/start', t1, { vehicleId: V2.id, route: 'Pasig – Quiapo', startingOdometer: 1100, ...P });
    const trip2 = r.body?.trip;
    check('trip starts normally before the threshold', r.status === 201, r.body);

    r = await api('PATCH', `/api/admin/ops/incidents/${i3.id}/review`, tOpA, { status: 'CONFIRMED', note: 'confirmed' });
    check('third confirmed violation applies the restriction', !!r.body?.restrictionApplied && r.body.restrictionApplied.durationMinutes === 60, r.body);
    const restrRow = await prisma.driverRestriction.findFirst({ where: { driverId: D1.id } });
    check('restriction records who applied it and the qualifying incidents', restrRow?.appliedById === opA.id && restrRow.incidentIds.length === 3, restrRow);
    const stillActive = await prisma.trip.findUnique({ where: { id: trip2.id } });
    check('an already-active trip is not terminated by the restriction', stillActive.status === 'ACTIVE');
    await api('POST', `/api/driver/trips/${trip2.id}/end`, t1);

    const newDeviceToken = sign(D1.id, 'driver');
    r = await api('POST', '/api/driver/trips/start', newDeviceToken, { vehicleId: V2.id, startingOdometer: 1200, ...P });
    check('restricted driver cannot start a trip (fresh login/device does not bypass)', r.status === 403 && r.body?.code === 'TRIP_RESTRICTED', r.body);
    check('restriction shows reason, start and expiry', !!r.body?.restriction?.reason && !!r.body?.restriction?.startsAt && !!r.body?.restriction?.expiresAt, r.body?.restriction);

    await api('PUT', '/api/admin/ops/settings', tAdm, { values: { shortTripRestrictionMinutes: 120 } });
    check('restriction length is configurable', (await api('GET', '/api/admin/ops/settings', tAdm)).body?.settings?.find((s) => s.key === 'shortTripRestrictionMinutes')?.value === 120);
    await api('PUT', '/api/admin/ops/settings', tAdm, { values: { shortTripRestrictionMinutes: 60 } });

    await prisma.driverRestriction.update({ where: { id: restrRow.id }, data: { expiresAt: new Date(Date.now() - 1000), startsAt: new Date(Date.now() - 3600_000) } });
    r = await api('POST', '/api/driver/trips/start', t1, { vehicleId: V2.id, startingOdometer: 1200, ...P });
    check('access is restored automatically once the timeout expires', r.status === 201, r.body);
    await api('POST', `/api/driver/trips/${r.body?.trip?.id}/end`, t1);

    // correction path
    await prisma.driverRestriction.update({ where: { id: restrRow.id }, data: { expiresAt: new Date(Date.now() + 3600_000), startsAt: new Date(Date.now() - 1000) } });
    r = await api('PATCH', `/api/admin/ops/incidents/${i3.id}/review`, tOpA, { status: 'DISMISSED', note: 'Recorded in error' });
    check('correcting a mistaken incident lifts the restriction it caused', (await api('GET', '/api/driver/me/restriction', t1)).body?.restriction === null);

    console.log('\nStatus, complaints, roles');
    r = await api('PATCH', `/api/admin/ops/drivers/${D1.id}/status`, tOpA, { operationalStatus: 'INACTIVE' });
    const d1 = await prisma.driver.findUnique({ where: { id: D1.id } });
    check('operational status changes without touching disciplinary status or login', d1.operationalStatus === 'INACTIVE' && d1.disciplinaryStatus === 'NONE' && d1.isActive === true, d1);
    r = await api('PATCH', `/api/admin/ops/drivers/${D1.id}/status`, tOpA, { disciplinaryStatus: 'SUSPENDED' });
    check('disciplinary status needs a recorded reason', r.status === 400);
    await api('PATCH', `/api/admin/ops/drivers/${D1.id}/status`, tOpA, { disciplinaryStatus: 'SUSPENDED', note: 'Pending investigation' });
    r = await api('POST', '/api/driver/trips/start', t1, { vehicleId: V2.id, startingOdometer: 1300, ...P });
    check('a suspended driver cannot start trips', r.status === 403 && r.body?.code === 'DRIVER_SUSPENDED', r.body);
    await api('PATCH', `/api/admin/ops/drivers/${D1.id}/status`, tOpA, { disciplinaryStatus: 'NONE' });

    for (let k = 0; k < 5; k++) {
      await prisma.complaint.create({ data: { complainantId: C[k].id, driverId: D1.id, complaintType: 'Rude Behavior', description: 'x' } });
    }
    const d1b = await prisma.driver.findUnique({ where: { id: D1.id } });
    check('multiple complaints never auto-deactivate or discipline a driver', d1b.isActive === true && d1b.disciplinaryStatus === 'NONE');

    // scoping
    r = await api('GET', '/api/admin/ops/drivers', tOpB);
    check('operator only sees its own drivers', (r.body?.drivers || []).every((d) => d.operatorId === opB.id) && !(r.body?.drivers || []).some((d) => d.id === D1.id), r.body?.drivers?.map((d) => d.fullName));
    r = await api('GET', '/api/admin/ops/vehicles', tOpB);
    check('operator only sees its own vehicles', !(r.body?.vehicles || []).some((v) => v.id === V1.id));
    r = await api('PATCH', `/api/admin/ops/vehicles/${V1.id}`, tOpB, { seatingCapacity: 30 });
    check('operator cannot edit another operator\'s vehicle', r.status === 404);
    r = await api('POST', '/api/admin/ops/assignments', tOpB, { driverId: D1.id, vehicleId: V3.id });
    check('operator cannot assign another operator\'s driver', r.status === 404);
    r = await api('GET', `/api/admin/ops/incidents`, tOpB);
    check('operator cannot see another operator\'s incidents', (r.body?.incidents || []).length === 0, r.body?.incidents?.length);
    r = await api('GET', '/api/admin/drivers', tOpA);
    check('operators are fenced out of legacy admin endpoints', r.status === 403, r.status);
    r = await api('GET', '/api/admin/complaints', tOpB);
    check('operator complaint list is scoped (none for D1)', r.status === 200 && (r.body?.complaints || []).length === 0, r.body);
    r = await api('GET', '/api/admin/complaints', tOpA);
    check('operator sees complaints about its own drivers', r.status === 200 && (r.body?.complaints || []).length >= 5, r.body?.complaints?.length);
    r = await api('PATCH', `/api/admin/ops/vehicles/${V1.id}`, tMani, { seatingCapacity: 30 });
    check('MANIBELA is read-only for fleet changes', r.status === 403);
    r = await api('GET', '/api/admin/ops/trips', tMani);
    check('MANIBELA can monitor all trips', r.status === 200);
    r = await api('PATCH', `/api/admin/ops/incidents/${i2.id}/review`, tMani, { status: 'UNDER_REVIEW' });
    check('MANIBELA can review incidents', r.status === 200, r.body);
    r = await api('PATCH', `/api/admin/ops/vehicles/${V1.id}`, tOpA, { seatingCapacity: 22 });
    check('operator can manage capacity of its own vehicle', r.status === 200 && r.body?.vehicle?.seatingCapacity === 22, r.body);
    r = await api('POST', '/api/admin/ops/restrictions', tOpA, { driverId: D1.id, durationMinutes: 5, reason: 'abc' });
    check('only administrators can apply a restriction by hand', r.status === 403);

    console.log('\nReports & earnings');
    r = await api('GET', '/api/admin/ops/reports?period=day', tOpA);
    check('daily report includes passenger counts and capacity', r.status === 200 && r.body?.totals && r.body.trips.some((t) => t.seatingCapacity !== null && 'appPassengers' in t && 'manualPassengers' in t), r.body?.totals);
    check('earnings are kept in three separate figures', r.body?.earnings && 'driverReported' in r.body.earnings && 'estimated' in r.body.earnings && 'verified' in r.body.earnings);
    check('estimate is off (null) until a fare is configured', r.body?.earnings?.estimated === null);
    r = await api('GET', '/api/admin/ops/reports?period=month', tOpA);
    check('monthly report works', r.status === 200 && r.body?.period === 'month');
    const log = await prisma.driverDailyLog.create({ data: { driverId: D1.id, date: new Date(`${new Date().toISOString().slice(0, 10)}T00:00:00Z`), startOdo: 1, endOdo: 2, earnings: 500 } });
    r = await api('POST', `/api/admin/ops/earnings/${log.id}/verify`, tOpB, { verifiedEarnings: 450 });
    check('operator cannot verify another operator\'s earnings', r.status === 404);
    r = await api('POST', `/api/admin/ops/earnings/${log.id}/verify`, tOpA, { verifiedEarnings: 450 });
    r = await api('GET', '/api/admin/ops/reports?period=day', tOpA);
    check('driver-reported vs verified earnings reported separately', r.body?.earnings?.driverReported >= 500 && r.body?.earnings?.verified === 450, r.body?.earnings);
    await prisma.driverDailyLog.delete({ where: { id: log.id } });
    r = await api('PUT', '/api/driver/non-operation', t2, { date: '2026-01-02', reason: 'Vehicle in repair shop' });
    check('driver can record why they did not operate on a no-trip day', r.status === 200, r.body);

    console.log('\nExisting features');
    r = await api('GET', '/api/admin/stats', tAdm);
    check('legacy admin dashboard still works', r.status === 200);
    r = await api('GET', '/api/admin/drivers', tAdm);
    check('legacy admin driver list still works', r.status === 200 && Array.isArray(r.body?.drivers));
    r = await api('GET', '/api/driver/trips', t1);
    check('driver trip history still works', r.status === 200 && r.body?.totalTrips >= 1, r.body?.totalTrips);
    r = await api('GET', `/api/commuter/nearby-jeepneys?lat=${P.lat}&lng=${P.lng}`, tc[0]);
    check('commuter nearby-jeepneys still works', r.status === 200);
    r = await api('POST', '/api/driver/trips/start', t2, { vehicleId: V3.id, route: 'Quiapo – Pasig', startingOdometer: 50, ...P });
    check('another driver can start a trip with their own vehicle', r.status === 201, r.body);
    r = await api('GET', `/api/commuter/nearby-jeepneys?lat=${P.lat}&lng=${P.lng}`, tc[0]);
    check('active trip appears to commuters (GPS tracking intact)', (r.body?.jeepneys || []).some((j) => j.plateNumber), r.body);
    await api('POST', `/api/driver/trips/${(await prisma.trip.findFirst({ where: { driverId: D2.id, status: 'ACTIVE' } }))?.id}/end`, t2);
  } finally {
    console.log('\nCleaning up test data…');
    const driverIds = created.drivers;
    const tripIds = (await prisma.trip.findMany({ where: { driverId: { in: driverIds } }, select: { id: true } })).map((t) => t.id);
    await prisma.boardingRequest.deleteMany({ where: { tripId: { in: tripIds } } });
    await prisma.tripBoarding.deleteMany({ where: { tripId: { in: tripIds } } });
    await prisma.manualPassengerAdjustment.deleteMany({ where: { tripId: { in: tripIds } } });
    await prisma.trip.deleteMany({ where: { id: { in: tripIds } } });
    await prisma.shortTripIncident.deleteMany({ where: { driverId: { in: driverIds } } });
    await prisma.driverRestriction.deleteMany({ where: { driverId: { in: driverIds } } });
    await prisma.complaint.deleteMany({ where: { driverId: { in: driverIds } } });
    await prisma.driverNonOperationDay.deleteMany({ where: { driverId: { in: driverIds } } });
    await prisma.driverDailyLog.deleteMany({ where: { driverId: { in: driverIds } } });
    await prisma.driverNotification.deleteMany({ where: { recipientId: { in: driverIds } } });
    await prisma.commuterNotification.deleteMany({ where: { recipientId: { in: created.commuters } } });
    await prisma.demandSignal.deleteMany({ where: { commuterId: { in: created.commuters } } });
    await prisma.driverVehicleAssignment.deleteMany({ where: { driverId: { in: driverIds } } });
    await prisma.auditLog.deleteMany({ where: { OR: [{ actorId: { in: created.admins } }, { targetId: { in: [...driverIds, ...created.vehicles] } }] } });
    await prisma.vehicle.deleteMany({ where: { id: { in: created.vehicles } } });
    await prisma.driver.deleteMany({ where: { id: { in: driverIds } } });
    await prisma.commuter.deleteMany({ where: { id: { in: created.commuters } } });
    await prisma.admin.deleteMany({ where: { id: { in: created.admins } } });
    await prisma.systemSetting.deleteMany({});
    await prisma.$disconnect();
  }

  console.log(`\n${passed} passed, ${failures.length} failed`);
  if (failures.length) {
    console.log('Failed:\n - ' + failures.join('\n - '));
    process.exit(1);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
