import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { Prisma } from '@prisma/client';
import { z } from 'zod';

import { prisma } from '../lib/prisma';
import { toE164 } from '../utils/phone';
import { isValidPlateNumber, normalizePlateNumber } from '../utils/plate';
import { toTitleCase } from '../utils/text';
import { generateDriverId } from '../utils/driverId';
import { generateQrToken } from '../utils/qrToken';
import { signAuthToken } from '../utils/jwt';
import { issueOtp, verifyOtp } from '../utils/otp';
import { formatDateOnly, manilaDayKey, manilaMidnight } from '../utils/date';
import { requireAuth } from '../middleware/auth';
import { uploadPhoto, uploadLicensePhotos, deleteUploadedPhoto, uploadBufferToCloudinary } from '../middleware/upload';
import { notifyDriver, notifyAdmin, notifyCommuter } from '../utils/notify';
import { authLimiter } from '../middleware/rateLimit';
import { compareFaces, fetchImageBuffer, FACE_MATCH_AUTO_CLEAR_SCORE } from '../lib/faceMatch';
import { distanceMeters, estimateEtaMinutes } from '../utils/geo';
import { getRoute } from '../lib/routingService';
import { bumpPeakOccupancy, getOccupancy, lockTrip } from '../lib/occupancy';
import { getActiveRestriction, toPublicRestriction } from '../lib/restrictions';

const router = Router();

// Unauthenticated + brute-forceable — see middleware/rateLimit.ts.
router.use(
  ['/signup', '/login', '/forgot-password', '/verify-otp', '/reset-password'],
  authLimiter,
);

function toPublicDriver(driver: {
  id: string;
  driverId: string;
  fullName: string;
  mobileNumber: string;
  plateNumber: string;
  dateOfBirth: Date | null;
  photoUrl: string | null;
  licenseNumber: string | null;
  licenseVerificationStatus: string | null;
}) {
  return {
    id: driver.id,
    driverId: driver.driverId,
    fullName: driver.fullName,
    mobileNumber: driver.mobileNumber,
    plateNumber: driver.plateNumber,
    dateOfBirth: driver.dateOfBirth ? formatDateOnly(driver.dateOfBirth) : null,
    photoUrl: driver.photoUrl,
    // Only ever set by an admin, alongside licenseVerificationStatus —
    // see PATCH /admin/drivers/:id/license-number. Shown to the driver
    // themselves once approved (see driver_license_number_screen.dart),
    // not just the bare "Verified" status.
    licenseNumber: driver.licenseNumber,
    licenseVerificationStatus: driver.licenseVerificationStatus,
  };
}

function toPublicTrip(trip: {
  id: string;
  driverId: string;
  route: string | null;
  status: string;
  currentLat: number | null;
  currentLng: number | null;
  startedAt: Date;
  endedAt: Date | null;
  startingOdometer?: number | null;
  plateNumber?: string | null;
  vehicleId?: string | null;
  capacitySnapshot?: number | null;
  manualPassengers?: number;
  isShortTrip: boolean;
  flagReason: string | null;
  driverExplanation: string | null;
  explanationSubmittedAt: Date | null;
  reviewStatus: string;
  reviewedAt: Date | null;
  adminReviewNote: string | null;
}) {
  return {
    id: trip.id,
    driverId: trip.driverId,
    route: trip.route,
    status: trip.status,
    currentLat: trip.currentLat,
    currentLng: trip.currentLng,
    startedAt: trip.startedAt,
    endedAt: trip.endedAt,
    startingOdometer: trip.startingOdometer ?? null,
    plateNumber: trip.plateNumber ?? null,
    vehicleId: trip.vehicleId ?? null,
    capacitySnapshot: trip.capacitySnapshot ?? null,
    manualPassengers: trip.manualPassengers ?? 0,
    isShortTrip: trip.isShortTrip,
    flagReason: trip.flagReason,
    driverExplanation: trip.driverExplanation,
    explanationSubmittedAt: trip.explanationSubmittedAt,
    reviewStatus: trip.reviewStatus,
    reviewedAt: trip.reviewedAt,
    // reviewedBy (an admin id) is deliberately left out — the driver has
    // no use for it and no visibility into the admin table.
    adminReviewNote: trip.adminReviewNote,
  };
}

// Two escalating tiers, both duration-based. Distance would sharpen this
// (a short trip that still covered real distance is probably genuine),
// but this app doesn't track a trip's traveled distance anywhere yet —
// only a live currentLat/currentLng snapshot, not a path — so duration
// is the only honest signal available. Server-side and fixed, not
// client-supplied, so neither the Flutter app nor any other caller can
// influence it.
//
// - Under 60s: almost certainly an accidental/test tap of Start Trip
//   immediately followed by End Trip, not a real completed run.
// - Under 5 minutes (but at least 60s): still far too short for a real
//   Pasig–Quiapo run even in light traffic — less likely a mis-tap, more
//   likely a genuinely aborted trip (breakdown, no passengers, gaming
//   the system), which is arguably the more useful signal for admin
//   review. Both tiers reuse the same isShortTrip/flagReason/review/
//   explanation pipeline — only the wording differs, so admins and
//   drivers can tell the two apart from the Flag Reason text alone.
const IMMEDIATE_TAP_THRESHOLD_MS = 60_000; // 1 minute
const BRIEF_TRIP_THRESHOLD_MS = 5 * 60_000; // 5 minutes

function computeShortTripFlag(startedAt: Date, endedAt: Date): { isShortTrip: boolean; flagReason: string | null } {
  const durationMs = endedAt.getTime() - startedAt.getTime();
  if (durationMs >= BRIEF_TRIP_THRESHOLD_MS) {
    return { isShortTrip: false, flagReason: null };
  }
  const totalSeconds = Math.max(0, Math.round(durationMs / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  if (durationMs < IMMEDIATE_TAP_THRESHOLD_MS) {
    return {
      isShortTrip: true,
      flagReason: `Trip lasted ${minutes}m ${seconds}s, below the 60-second minimum.`,
    };
  }
  return {
    isShortTrip: true,
    flagReason: `Trip lasted ${minutes}m ${seconds}s — unusually brief for a completed Pasig–Quiapo run.`,
  };
}

// ---------------------------------------------------------------------------
// SIGN UP
// ---------------------------------------------------------------------------
// Drivers don't self-register in the app — an operator/admin creates their
// account (see DriverSession's doc comment on the Flutter side). There's no
// operator role/auth in this schema yet, so this endpoint is left open for
// now (used by prisma/seed.ts and manual testing); gate it behind an
// operator role before this ever goes further than local dev.

const signupSchema = z.object({
  fullName: z.string().trim().min(1).transform(toTitleCase),
  mobileNumber: z.string().trim().min(1),
  password: z.string().min(8),
  plateNumber: z
    .string()
    .trim()
    .min(1)
    .transform((value) => normalizePlateNumber(value))
    .refine(isValidPlateNumber, {
      message: 'Plate number must be 3 letters followed by 3 or 4 numbers (e.g. ABC123 or ABC1234).',
    }),
});

router.post('/signup', async (req, res, next) => {
  try {
    const body = signupSchema.parse(req.body);
    const mobileNumber = toE164(body.mobileNumber);

    const existing = await prisma.driver.findUnique({ where: { mobileNumber } });
    if (existing) {
      res.status(409).json({ error: 'This number is already registered.' });
      return;
    }

    const passwordHash = await bcrypt.hash(body.password, 10);
    const driver = await prisma.driver.create({
      data: {
        driverId: await generateDriverId(),
        fullName: body.fullName,
        mobileNumber,
        passwordHash,
        plateNumber: body.plateNumber,
        qrToken: await generateQrToken(),
      },
    });

    const token = signAuthToken({ sub: driver.id, role: 'driver' });
    res.status(201).json({ token, driver: toPublicDriver(driver) });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// LOGIN
// ---------------------------------------------------------------------------

const loginSchema = z.object({
  mobileNumber: z.string().trim().min(1),
  password: z.string().min(1),
});

router.post('/login', async (req, res, next) => {
  try {
    const body = loginSchema.parse(req.body);
    const mobileNumber = toE164(body.mobileNumber);

    const driver = await prisma.driver.findUnique({ where: { mobileNumber } });
    if (!driver) {
      res.status(404).json({
        error: "This number isn't registered. Contact your operator to get a driver account.",
      });
      return;
    }

    const valid = await bcrypt.compare(body.password, driver.passwordHash);
    if (!valid) {
      res.status(401).json({ error: 'Incorrect password.' });
      return;
    }

    if (!driver.isActive) {
      res.status(403).json({ error: 'This account has been deactivated. Contact your operator for help.' });
      return;
    }

    const token = signAuthToken({ sub: driver.id, role: 'driver' });
    res.json({ token, driver: toPublicDriver(driver) });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// FORGOT PASSWORD — request + verify OTP, then reset
// ---------------------------------------------------------------------------

const mobileOnlySchema = z.object({ mobileNumber: z.string().trim().min(1) });

router.post('/forgot-password', async (req, res, next) => {
  try {
    const body = mobileOnlySchema.parse(req.body);
    const mobileNumber = toE164(body.mobileNumber);

    const driver = await prisma.driver.findUnique({ where: { mobileNumber } });
    if (!driver) {
      res.status(404).json({ error: 'This number is not registered.' });
      return;
    }

    await issueOtp(mobileNumber, 'PASSWORD_RESET');
    res.json({ message: 'A verification code has been sent.' });
  } catch (err) {
    next(err);
  }
});

const verifyOtpSchema = z.object({
  mobileNumber: z.string().trim().min(1),
  code: z.string().length(6),
});

router.post('/verify-otp', async (req, res, next) => {
  try {
    const body = verifyOtpSchema.parse(req.body);
    const mobileNumber = toE164(body.mobileNumber);

    // Doesn't consume the code — this is just early feedback ("yes, that's
    // right") before the app moves on to reset-password, which is the
    // call that actually spends it.
    const ok = await verifyOtp(mobileNumber, 'PASSWORD_RESET', body.code, { consume: false });
    if (!ok) {
      res.status(400).json({ error: 'Invalid or expired code.' });
      return;
    }

    res.json({ verified: true });
  } catch (err) {
    next(err);
  }
});

const resetPasswordSchema = z.object({
  mobileNumber: z.string().trim().min(1),
  code: z.string().length(6),
  newPassword: z.string().min(8),
});

router.post('/reset-password', async (req, res, next) => {
  try {
    const body = resetPasswordSchema.parse(req.body);
    const mobileNumber = toE164(body.mobileNumber);

    // Expiry isn't re-checked here — that's only meant to bound the OTP
    // screen itself, not how long someone takes on the password fields
    // after (see verifyOtp's checkExpiry doc comment).
    const ok = await verifyOtp(mobileNumber, 'PASSWORD_RESET', body.code, { checkExpiry: false });
    if (!ok) {
      res.status(400).json({ error: 'Invalid or expired code.' });
      return;
    }

    const driver = await prisma.driver.findUnique({ where: { mobileNumber } });
    if (!driver) {
      res.status(404).json({ error: 'This number is not registered.' });
      return;
    }

    const passwordHash = await bcrypt.hash(body.newPassword, 10);
    await prisma.driver.update({ where: { id: driver.id }, data: { passwordHash } });

    res.json({ message: 'Password reset successfully.' });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// PROFILE (authenticated)
// ---------------------------------------------------------------------------

router.get('/me', requireAuth('driver'), async (req, res, next) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
    if (!driver) {
      res.status(404).json({ error: 'Account not found.' });
      return;
    }
    res.json({ driver: toPublicDriver(driver) });
  } catch (err) {
    next(err);
  }
});

// dateOfBirth deliberately isn't editable here — only an admin can set it
// now, via PATCH /admin/drivers/:id/date-of-birth (see that endpoint's
// doc comment for why).
const updateProfileSchema = z.object({
  fullName: z
    .string()
    .trim()
    .min(1)
    .optional()
    .transform((value) => (value === undefined ? undefined : toTitleCase(value))),
  photoUrl: z.string().trim().min(1).nullable().optional(),
});

router.patch('/me', requireAuth('driver'), async (req, res, next) => {
  try {
    const body = updateProfileSchema.parse(req.body);

    const driver = await prisma.driver.update({
      where: { id: req.auth!.sub },
      data: {
        fullName: body.fullName,
        photoUrl: body.photoUrl,
      },
    });

    res.json({ driver: toPublicDriver(driver) });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// CHANGE MOBILE NUMBER (authenticated) — OTP-gated so a number can't be
// swapped onto an account without proving the caller actually controls it.
// send-otp texts the code to the NEW number (not the account's current
// one — there's nothing to prove about a number already on file); verify
// checks it and, only then, actually moves the account onto it.
// ---------------------------------------------------------------------------

const sendPhoneChangeOtpSchema = z.object({ mobileNumber: z.string().trim().min(1) });

router.post('/me/phone/send-otp', requireAuth('driver'), async (req, res, next) => {
  try {
    const body = sendPhoneChangeOtpSchema.parse(req.body);
    const mobileNumber = toE164(body.mobileNumber);

    const existing = await prisma.driver.findUnique({ where: { mobileNumber } });
    if (existing && existing.id !== req.auth!.sub) {
      res.status(409).json({ error: 'This mobile number is already registered to another account.' });
      return;
    }

    await issueOtp(mobileNumber, 'PHONE_CHANGE');
    res.json({ message: 'A verification code has been sent.' });
  } catch (err) {
    next(err);
  }
});

const verifyPhoneChangeOtpSchema = z.object({
  mobileNumber: z.string().trim().min(1),
  code: z.string().length(6),
});

router.post('/me/phone/verify', requireAuth('driver'), async (req, res, next) => {
  try {
    const body = verifyPhoneChangeOtpSchema.parse(req.body);
    const mobileNumber = toE164(body.mobileNumber);

    const ok = await verifyOtp(mobileNumber, 'PHONE_CHANGE', body.code);
    if (!ok) {
      res.status(400).json({ error: 'Invalid or expired code.' });
      return;
    }

    // Re-checked here (not just at send-otp time) in case someone else
    // claimed this number during the window the code was outstanding.
    const existing = await prisma.driver.findUnique({ where: { mobileNumber } });
    if (existing && existing.id !== req.auth!.sub) {
      res.status(409).json({ error: 'This mobile number is already registered to another account.' });
      return;
    }

    const driver = await prisma.driver.update({
      where: { id: req.auth!.sub },
      data: { mobileNumber },
    });

    res.json({ driver: toPublicDriver(driver) });
  } catch (err) {
    next(err);
  }
});

// multipart/form-data, field name "photo" — a plain URL/JSON field can't
// carry binary image data, hence the separate endpoint (and separate
// content type) from PATCH /me above.
router.post('/me/photo', requireAuth('driver'), (req, res, next) => {
  uploadPhoto(req, res, async (err) => {
    if (err) {
      res.status(400).json({ error: err instanceof Error ? err.message : 'Upload failed.' });
      return;
    }
    if (!req.file) {
      res.status(400).json({ error: 'No photo was uploaded.' });
      return;
    }

    try {
      const existing = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
      if (!existing) {
        res.status(404).json({ error: 'Account not found.' });
        return;
      }

      const photoUrl = await uploadBufferToCloudinary(req.file.buffer, 'profile-photos');
      const driver = await prisma.driver.update({
        where: { id: existing.id },
        data: { photoUrl },
      });

      // Only after the DB update succeeds — never leave the record
      // pointing at a file that got deleted out from under it.
      deleteUploadedPhoto(existing.photoUrl);

      res.json({ driver: toPublicDriver(driver) });
    } catch (err2) {
      next(err2);
    }
  });
});

// Driver-submitted license photo + selfie — Settings -> License Number
// -> upload or take photo -> submit (see TODO.md re: no OCR/auto-detect
// on the license number itself). Reuses the same uploadLicensePhotos
// middleware the (now-removed) admin-side upload used — all three files
// are required here, unlike that old endpoint where either license side
// alone was accepted. A high enough faceMatchScore (selfie vs. license
// front, same mechanism/threshold as commuter signup — see
// lib/faceMatch.ts) auto-clears straight to APPROVED, letting the
// driver start trips immediately with no admin involved; otherwise this
// sets PENDING same as before, for an admin to review manually.
router.post('/me/license-photo', requireAuth('driver'), (req, res, next) => {
  uploadLicensePhotos(req, res, async (err) => {
    if (err) {
      res.status(400).json({ error: err instanceof Error ? err.message : 'Upload failed.' });
      return;
    }

    try {
      const files = req.files as
        | { licenseFront?: Express.Multer.File[]; licenseBack?: Express.Multer.File[]; selfie?: Express.Multer.File[] }
        | undefined;
      const front = files?.licenseFront?.[0];
      const back = files?.licenseBack?.[0];
      const selfie = files?.selfie?.[0];
      if (!front || !back || !selfie) {
        res.status(400).json({ error: 'Please provide the front and back of your license, and a selfie.' });
        return;
      }

      const existing = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
      if (!existing) {
        res.status(404).json({ error: 'Account not found.' });
        return;
      }

      const [licenseFrontUrl, licenseBackUrl, selfieUrl] = await Promise.all([
        uploadBufferToCloudinary(front.buffer, 'license-photos', { sensitive: true }),
        uploadBufferToCloudinary(back.buffer, 'license-photos', { sensitive: true }),
        uploadBufferToCloudinary(selfie.buffer, 'selfies', { sensitive: true }),
      ]);

      // Never blocks submission — any failure (no face found, model
      // error, fetch failure) just degrades to a null score, which
      // falls back to the same PENDING/manual-review path as before.
      let faceMatchScore: number | null = null;
      try {
        const [selfieBuffer, licenseBuffer] = await Promise.all([
          fetchImageBuffer(selfieUrl),
          fetchImageBuffer(licenseFrontUrl),
        ]);
        faceMatchScore = await compareFaces(selfieBuffer, licenseBuffer);
      } catch {
        faceMatchScore = null;
      }
      const autoCleared = faceMatchScore !== null && faceMatchScore >= FACE_MATCH_AUTO_CLEAR_SCORE;

      const driver = await prisma.driver.update({
        where: { id: existing.id },
        data: {
          licenseFrontUrl,
          licenseBackUrl,
          selfieUrl,
          faceMatchScore,
          licenseVerificationStatus: autoCleared ? 'APPROVED' : 'PENDING',
        },
      });

      deleteUploadedPhoto(existing.licenseFrontUrl);
      deleteUploadedPhoto(existing.licenseBackUrl);
      deleteUploadedPhoto(existing.selfieUrl);

      if (!autoCleared) {
        await notifyAdmin({
          title: 'Driver license submitted',
          message: `${driver.fullName} (${driver.driverId}) submitted license photos for review.`,
          type: 'LICENSE_SUBMITTED',
          referenceId: driver.id,
        });
      }

      res.json({ driver: toPublicDriver(driver) });
    } catch (err2) {
      next(err2);
    }
  });
});

const changePasswordSchema = z.object({
  currentPassword: z.string().min(1),
  newPassword: z.string().min(8),
});

router.patch('/me/password', requireAuth('driver'), async (req, res, next) => {
  try {
    const body = changePasswordSchema.parse(req.body);

    const driver = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
    if (!driver) {
      res.status(404).json({ error: 'Account not found.' });
      return;
    }

    const valid = await bcrypt.compare(body.currentPassword, driver.passwordHash);
    if (!valid) {
      res.status(400).json({ error: 'Current password is incorrect.' });
      return;
    }

    const passwordHash = await bcrypt.hash(body.newPassword, 10);
    await prisma.driver.update({ where: { id: driver.id }, data: { passwordHash } });

    res.json({ message: 'Password updated.' });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// TRIPS — start/end + periodic location pings while active. This is what
// actually persists a trip server-side; DriverActiveTrip on the Flutter
// side still owns the in-app GPS-following UI, but now also calls these
// so the admin live map (and passenger boarding counts below) reflect
// something real instead of only existing on the driver's own device.
// ---------------------------------------------------------------------------

const startTripSchema = z
  .object({
    route: z.string().trim().min(1).nullable().optional(),
    // The driver's position at the moment they tap Start Trip. Seeds the new
    // trip's location so the jeepney is on the commuters' map from the very
    // first second — otherwise a trip has no position at all until the first
    // GPS *movement* update arrives, and a jeepney waiting at the terminal
    // (the usual moment a trip is started) would stay invisible until it
    // moved. Both or neither.
    lat: z.number().min(-90).max(90).optional(),
    lng: z.number().min(-180).max(180).optional(),
    // The vehicle's current odometer (km), required to start a NEW trip (not
    // to resume one already ACTIVE). NaN/negative/absurd values are rejected
    // here rather than trusted from the app's own check.
    startingOdometer: z.number().finite().min(0).max(9_999_999).optional(),
    // Set by the app only after the driver explicitly confirms an odometer
    // that is lower than the vehicle's last recorded reading (see the
    // ODOMETER_LOWER_THAN_LAST response below).
    confirmLowerOdometer: z.boolean().optional(),
    // Which of the driver's assigned jeepneys they are driving. Required to
    // start a NEW trip; ignored when resuming one already ACTIVE (a trip's
    // vehicle can never change).
    vehicleId: z.string().trim().min(1).optional(),
  })
  .refine((body) => (body.lat === undefined) === (body.lng === undefined), {
    message: 'lat and lng must be sent together.',
    path: ['lat'],
  });

router.post('/trips/start', requireAuth('driver'), async (req, res, next) => {
  try {
    const body = startTripSchema.parse(req.body);

    // Real enforcement, not just a UI gate — the app already blocks
    // reaching this screen when unverified (see driver_dashboard_screen's
    // _handleStartTrip), but this is what actually stops it if that's
    // ever bypassed.
    const driver = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
    if (driver?.licenseVerificationStatus !== 'APPROVED') {
      res.status(403).json({
        error: 'Your license must be verified before you can start a trip.',
        code: 'LICENSE_NOT_VERIFIED',
      });
      return;
    }

    const hasLocation = body.lat !== undefined && body.lng !== undefined;

    const existingActive = await prisma.trip.findFirst({
      where: { driverId: req.auth!.sub, status: 'ACTIVE' },
    });
    if (existingActive) {
      // Re-tapping Start Trip (or the app restarting mid-trip and resuming
      // this same trip) also counts as a fresh location fix — otherwise a
      // trip whose last ping went stale would stay hidden from commuters
      // until the next movement update.
      const resumed = hasLocation
        ? await prisma.trip.update({
            where: { id: existingActive.id },
            data: { currentLat: body.lat, currentLng: body.lng, locationUpdatedAt: new Date() },
          })
        : existingActive;
      res.json({ trip: toPublicTrip(resumed), occupancy: await getOccupancy(prisma, resumed.id) });
      return;
    }

    // Disciplinary gates — all judged on the server, from the database, so a
    // logout, reinstall or second phone changes nothing. They only stop a NEW
    // trip; one already ACTIVE (resumed above) is never cut off by them.
    if (driver.disciplinaryStatus === 'SUSPENDED') {
      res.status(403).json({
        error: 'Your account is suspended from driving. Please contact your operator.',
        code: 'DRIVER_SUSPENDED',
      });
      return;
    }
    const restriction = await getActiveRestriction(driver.id);
    if (restriction) {
      res.status(403).json({
        error: 'You are temporarily restricted from starting a new trip.',
        code: 'TRIP_RESTRICTED',
        restriction: toPublicRestriction(restriction),
      });
      return;
    }

    // The vehicle must be one this driver is currently assigned to — the
    // list the app shows comes from GET /vehicles, but this is what actually
    // stops someone sending another jeepney's id.
    if (!body.vehicleId) {
      res.status(400).json({
        error: 'Select the jeepney you are driving before starting a trip.',
        code: 'VEHICLE_REQUIRED',
      });
      return;
    }
    const assignment = await prisma.driverVehicleAssignment.findFirst({
      where: { driverId: driver.id, vehicleId: body.vehicleId, revokedAt: null },
      include: { vehicle: true },
    });
    if (!assignment || !assignment.vehicle.isActive) {
      res.status(403).json({
        error: 'That jeepney is not assigned to you.',
        code: 'VEHICLE_NOT_ASSIGNED',
      });
      return;
    }
    const vehicle = assignment.vehicle;
    if (vehicle.seatingCapacity === null) {
      res.status(409).json({
        error: `Seating capacity for ${vehicle.plateNumber} has not been set yet. Ask your operator to enter it.`,
        code: 'VEHICLE_CAPACITY_NOT_SET',
      });
      return;
    }
    const busy = await prisma.trip.findFirst({
      where: { vehicleId: vehicle.id, status: 'ACTIVE' },
      select: { id: true },
    });
    if (busy) {
      res.status(409).json({
        error: `${vehicle.plateNumber} is already on an active trip.`,
        code: 'VEHICLE_IN_USE',
      });
      return;
    }

    // A new trip must carry its starting odometer — saved in the same
    // create() below, so there is never an ACTIVE trip without one.
    if (body.startingOdometer === undefined) {
      res.status(400).json({
        error: "Please enter the vehicle's current odometer reading.",
        code: 'ODOMETER_REQUIRED',
      });
      return;
    }

    // The same vehicle's most recent earlier reading — a lower one is almost
    // always a typo, but not certain (a replaced odometer, a mistyped earlier
    // entry), so it needs the driver's explicit confirmation rather than
    // being a hard block that could lock a vehicle out of starting trips.
    if (!body.confirmLowerOdometer) {
      const previous = await prisma.trip.findFirst({
        where: { plateNumber: vehicle.plateNumber, startingOdometer: { not: null } },
        orderBy: { startedAt: 'desc' },
        select: { startingOdometer: true },
      });
      if (previous?.startingOdometer != null && body.startingOdometer < previous.startingOdometer) {
        res.status(409).json({
          error: `That's lower than the last recorded reading for this vehicle (${previous.startingOdometer} km).`,
          code: 'ODOMETER_LOWER_THAN_LAST',
          lastOdometer: previous.startingOdometer,
        });
        return;
      }
    }

    // No "Trip Started" notification — the driver just tapped the button
    // that caused this, so they already know; a notification for it would
    // just be an echo. "Trip Completed" (below, in /trips/:id/end) stays,
    // since it doubles as a record that the trip was actually recorded.
    let trip;
    try {
      trip = await prisma.trip.create({
        data: {
          driverId: req.auth!.sub,
          route: body.route ?? null,
          startingOdometer: body.startingOdometer,
          plateNumber: vehicle.plateNumber,
          vehicleId: vehicle.id,
          capacitySnapshot: vehicle.seatingCapacity,
          ...(hasLocation ? { currentLat: body.lat, currentLng: body.lng, locationUpdatedAt: new Date() } : {}),
        },
      });
    } catch (err) {
      // Two drivers raced for the same jeepney — the partial unique index on
      // ACTIVE trips per vehicle lets exactly one through.
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
        res.status(409).json({ error: `${vehicle.plateNumber} is already on an active trip.`, code: 'VEHICLE_IN_USE' });
        return;
      }
      throw err;
    }

    // Starting to drive means operating — flips an INACTIVE driver back.
    if (driver.operationalStatus !== 'ACTIVE') {
      await prisma.driver.update({ where: { id: driver.id }, data: { operationalStatus: 'ACTIVE' } });
    }

    res.status(201).json({ trip: toPublicTrip(trip), occupancy: await getOccupancy(prisma, trip.id) });
  } catch (err) {
    next(err);
  }
});

router.get('/trips/active', requireAuth('driver'), async (req, res, next) => {
  try {
    const trip = await prisma.trip.findFirst({
      where: { driverId: req.auth!.sub, status: 'ACTIVE' },
    });
    res.json({
      trip: trip ? toPublicTrip(trip) : null,
      occupancy: trip ? await getOccupancy(prisma, trip.id) : null,
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// VEHICLES — the jeepneys this driver is authorized to drive. Capacity comes
// from the vehicle record, never assumed. `inUse` tells the app a jeepney is
// already on an active trip (it can't be started again until that ends).
// ---------------------------------------------------------------------------
router.get('/vehicles', requireAuth('driver'), async (req, res, next) => {
  try {
    const assignments = await prisma.driverVehicleAssignment.findMany({
      where: { driverId: req.auth!.sub, revokedAt: null, vehicle: { isActive: true } },
      include: { vehicle: true },
      orderBy: { assignedAt: 'asc' },
    });
    const activeTrips = await prisma.trip.findMany({
      where: { vehicleId: { in: assignments.map((a) => a.vehicleId) }, status: 'ACTIVE' },
      select: { vehicleId: true, driverId: true },
    });
    const inUse = new Map(activeTrips.map((t) => [t.vehicleId, t.driverId]));

    res.json({
      vehicles: assignments.map((a) => ({
        id: a.vehicle.id,
        plateNumber: a.vehicle.plateNumber,
        seatingCapacity: a.vehicle.seatingCapacity,
        capacityConfigured: a.vehicle.seatingCapacity !== null,
        inUse: inUse.has(a.vehicleId),
        inUseByMe: inUse.get(a.vehicleId) === req.auth!.sub,
      })),
    });
  } catch (err) {
    next(err);
  }
});

// The caller's current trip-start restriction, if any (server time).
router.get('/me/restriction', requireAuth('driver'), async (req, res, next) => {
  try {
    const driver = await prisma.driver.findUnique({
      where: { id: req.auth!.sub },
      select: { disciplinaryStatus: true, operationalStatus: true },
    });
    const restriction = await getActiveRestriction(req.auth!.sub);
    const pendingExplanations = await prisma.shortTripIncident.count({
      where: { driverId: req.auth!.sub, status: 'PENDING_EXPLANATION' },
    });
    res.json({
      pendingExplanations,
      restriction: restriction ? toPublicRestriction(restriction) : null,
      disciplinaryStatus: driver?.disciplinaryStatus ?? 'NONE',
      operationalStatus: driver?.operationalStatus ?? 'ACTIVE',
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// PASSENGER COUNT — live occupancy plus the driver's manual +1/-1 for riders
// who don't use the app. Every change is capacity-checked and audited, and
// done under the trip's row lock so concurrent boardings can't overfill.
// ---------------------------------------------------------------------------
router.get('/trips/:id/occupancy', requireAuth('driver'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const trip = await prisma.trip.findUnique({ where: { id }, select: { driverId: true } });
    if (!trip || trip.driverId !== req.auth!.sub) {
      res.status(404).json({ error: 'Trip not found.' });
      return;
    }
    res.json({ occupancy: await getOccupancy(prisma, id) });
  } catch (err) {
    next(err);
  }
});

const manualPassengerSchema = z.object({
  delta: z.union([z.literal(1), z.literal(-1)]),
  // Idempotency key — a double tap / retried request changes the count once.
  clientRequestId: z.string().trim().min(1).max(100).optional(),
});

router.post('/trips/:id/passengers', requireAuth('driver'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = manualPassengerSchema.parse(req.body);
    const driverId = req.auth!.sub;

    const result = await prisma.$transaction(async (tx) => {
      await lockTrip(tx, id);
      const trip = await tx.trip.findUnique({ where: { id } });
      if (!trip || trip.driverId !== driverId) return { error: 404 as const };
      if (trip.status !== 'ACTIVE') return { error: 'ENDED' as const };

      if (body.clientRequestId) {
        const dup = await tx.manualPassengerAdjustment.findUnique({
          where: { driverId_clientRequestId: { driverId, clientRequestId: body.clientRequestId } },
        });
        if (dup) return { occupancy: await getOccupancy(tx, id), duplicate: true, adjustmentId: dup.id };
      }

      const before = await getOccupancy(tx, id);
      if (!before) return { error: 404 as const };

      if (body.delta === 1) {
        if (trip.vehicleId && before.seatingCapacity === null) return { error: 'CAPACITY_UNKNOWN' as const };
        if (before.seatingCapacity !== null && before.totalPassengers + 1 > before.seatingCapacity) {
          return { error: 'FULL' as const, occupancy: before };
        }
      } else if (trip.manualPassengers <= 0) {
        return { error: 'ZERO' as const, occupancy: before };
      }

      const updated = await tx.trip.update({
        where: { id },
        data: { manualPassengers: { increment: body.delta } },
      });
      const adjustment = await tx.manualPassengerAdjustment.create({
        data: {
          tripId: id,
          vehicleId: trip.vehicleId,
          driverId,
          delta: body.delta,
          countAfter: updated.manualPassengers,
          clientRequestId: body.clientRequestId ?? null,
        },
      });
      const after = await getOccupancy(tx, id);
      if (after) await bumpPeakOccupancy(tx, id, after.totalPassengers);
      return { occupancy: after, adjustmentId: adjustment.id };
    });

    if ('error' in result) {
      if (result.error === 404) res.status(404).json({ error: 'Trip not found.' });
      else if (result.error === 'ENDED') res.status(409).json({ error: 'This trip has already ended.', code: 'TRIP_ENDED' });
      else if (result.error === 'CAPACITY_UNKNOWN')
        res.status(409).json({ error: "This jeepney's seating capacity isn't set up yet.", code: 'CAPACITY_UNKNOWN' });
      else if (result.error === 'FULL')
        res.status(409).json({ error: 'The jeepney is full. No more passengers can be added.', code: 'JEEPNEY_FULL', occupancy: result.occupancy });
      else
        res.status(409).json({ error: 'There are no manually-counted passengers to remove.', code: 'MANUAL_COUNT_ZERO', occupancy: result.occupancy });
      return;
    }
    res.json(result);
  } catch (err) {
    next(err);
  }
});

// Undo the most recent manual change (the fix for an accidental tap). Written
// as a new, reversing row — the original stays in the audit trail. Only the
// latest un-reversed change can be undone, and an undo can't be undone.
router.post('/trips/:id/passengers/undo', requireAuth('driver'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const driverId = req.auth!.sub;

    const result = await prisma.$transaction(async (tx) => {
      await lockTrip(tx, id);
      const trip = await tx.trip.findUnique({ where: { id } });
      if (!trip || trip.driverId !== driverId) return { error: 404 as const };
      if (trip.status !== 'ACTIVE') return { error: 'ENDED' as const };

      const last = await tx.manualPassengerAdjustment.findFirst({
        where: { tripId: id, undoOfId: null },
        orderBy: { createdAt: 'desc' },
      });
      const alreadyUndone = last
        ? await tx.manualPassengerAdjustment.findUnique({ where: { undoOfId: last.id } })
        : null;
      if (!last || alreadyUndone) return { error: 'NOTHING' as const };

      const delta = -last.delta;
      const before = await getOccupancy(tx, id);
      if (!before) return { error: 404 as const };
      if (delta === 1 && before.seatingCapacity !== null && before.totalPassengers + 1 > before.seatingCapacity) {
        return { error: 'FULL' as const };
      }
      if (delta === -1 && trip.manualPassengers <= 0) return { error: 'NOTHING' as const };

      const updated = await tx.trip.update({ where: { id }, data: { manualPassengers: { increment: delta } } });
      await tx.manualPassengerAdjustment.create({
        data: { tripId: id, vehicleId: trip.vehicleId, driverId, delta, countAfter: updated.manualPassengers, undoOfId: last.id },
      });
      return { occupancy: await getOccupancy(tx, id) };
    });

    if ('error' in result) {
      if (result.error === 404) res.status(404).json({ error: 'Trip not found.' });
      else if (result.error === 'ENDED') res.status(409).json({ error: 'This trip has already ended.', code: 'TRIP_ENDED' });
      else if (result.error === 'FULL')
        res.status(409).json({ error: 'Undoing that would put the jeepney over capacity.', code: 'JEEPNEY_FULL' });
      else res.status(409).json({ error: 'Nothing to undo.', code: 'NOTHING_TO_UNDO' });
      return;
    }
    res.json(result);
  } catch (err) {
    next(err);
  }
});

const tripLocationSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
});

router.patch('/trips/:id/location', requireAuth('driver'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = tripLocationSchema.parse(req.body);

    const trip = await prisma.trip.findUnique({ where: { id } });
    if (!trip || trip.driverId !== req.auth!.sub) {
      res.status(404).json({ error: 'Trip not found.' });
      return;
    }
    if (trip.status !== 'ACTIVE') {
      res.status(400).json({ error: 'This trip has already ended.' });
      return;
    }

    const updated = await prisma.trip.update({
      where: { id },
      data: { currentLat: body.lat, currentLng: body.lng, locationUpdatedAt: new Date() },
    });

    res.json({ trip: toPublicTrip(updated) });
  } catch (err) {
    next(err);
  }
});

router.post('/trips/:id/end', requireAuth('driver'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;

    const trip = await prisma.trip.findUnique({ where: { id } });
    if (!trip || trip.driverId !== req.auth!.sub) {
      res.status(404).json({ error: 'Trip not found.' });
      return;
    }
    if (trip.status !== 'ACTIVE') {
      res.json({ trip: toPublicTrip(trip) });
      return;
    }

    const endedAt = new Date();
    const { isShortTrip, flagReason } = computeShortTripFlag(trip.startedAt, endedAt);


    const updated = await prisma.trip.update({
      where: { id },
      data: { status: 'COMPLETED', endedAt, isShortTrip, flagReason },
    });

    // The trip is now really ended in the database — answer the driver's app
    // right away; End Trip is waited on by a person staring at a button, so
    // everything below is follow-up work that must not hold the response.
    // (Notifications used to run before the response, and then so did the
    // boarding clean-up; if anything below threw, an already-ended trip came
    // back to the app as an error.)
    res.json({ trip: toPublicTrip(updated) });

    try {
      // Boarding verifications still waiting on this trip can never complete.
      await prisma.boardingRequest.updateMany({
        where: { tripId: id, status: 'PENDING' },
        data: {
          status: 'FAILED',
          failureCode: 'TRIP_ENDED',
          failureMessage: "This jeepney's trip has ended.",
          resolvedAt: endedAt,
        },
      });

      // A commuter still marked onboard when the *driver* ends the trip
      // (as opposed to tapping their own "Para Po"/End Trip — see POST
      // /api/commuter/alight) would otherwise stay stuck with alightedAt
      // still null forever: their own active-trip check already stops
      // showing them as riding once trip.status flips off ACTIVE, but the
      // boarding record itself never closes, and they're never told the
      // trip actually ended. Close every open boarding out here too, same
      // as a real alight, and let each of them know.
      const openBoardings = await prisma.tripBoarding.findMany({
        where: { tripId: id, alightedAt: null },
        select: { commuterId: true },
      });
      if (openBoardings.length > 0) {
        await prisma.tripBoarding.updateMany({
          where: { tripId: id, alightedAt: null },
          data: { alightedAt: endedAt, status: 'COMPLETED' },
        });
      }

      await Promise.all(
        openBoardings.map((b) =>
          notifyCommuter({
            recipientId: b.commuterId,
            title: 'Trip Completed',
            message: 'Your trip has ended. Thanks for riding with ManibelApp!',
            type: 'TRIP_COMPLETED',
            referenceId: updated.id,
          }),
        ),
      );

      await notifyDriver({
        recipientId: req.auth!.sub,
        title: 'Trip Completed',
        message: updated.route ? `${updated.route} has ended.` : 'Your trip has ended.',
        type: 'TRIP_COMPLETED',
        referenceId: updated.id,
      });

      if (isShortTrip) {
        const routeLabel = updated.route ?? 'your trip';
        await notifyDriver({
          recipientId: req.auth!.sub,
          title: 'Short Trip Flagged',
          message: `${routeLabel} was flagged as unusually short (${flagReason}). Tap to explain what happened.`,
          type: 'TRIP_SHORT_FLAGGED',
          referenceId: updated.id,
        });

        // Admins otherwise only find out once a driver bothers to submit an
        // explanation (see PATCH /trips/:id/explanation) — this way a
        // flagged trip that never gets explained still surfaces for review.
        const driver = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
        await notifyAdmin({
          title: 'Short trip flagged',
          message: `${driver?.fullName ?? 'A driver'} (${driver?.plateNumber ?? '—'})'s trip on ${routeLabel} was flagged as unusually short — needs review.`,
          type: 'TRIP_SHORT_FLAGGED',
          referenceId: updated.driverId,
        });
      }
    } catch (notifyErr) {
      console.error('End-trip notifications failed (trip already ended):', notifyErr);
    }
  } catch (err) {
    next(err);
  }
});

// The two fixed routes this fleet services — see DRIVER_ROUTES's doc
// comment in admin.ts for why this is hardcoded rather than a `SELECT
// DISTINCT route` per driver.
const DRIVER_ROUTES = ['Pasig – Quiapo', 'Quiapo – Pasig'] as const;

// Completed trips only — the app's own Trip History screen has nothing to
// show for a still-ACTIVE trip (that's what the dashboard/in-progress
// screen are for). Backs DriverHistoryScreen's paginated list — "Load 20
// initially, Load More for 20 more" is just this driver tapping through
// increasing `page` values with `limit` fixed at 20, same page/limit
// pagination the admin site's equivalent view uses (as `page`/`pageSize`
// there — named differently only because that's this app's existing
// per-platform convention, see GET /admin/trips).
const tripHistoryQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  dateFrom: z.coerce.date().optional(),
  dateTo: z.coerce.date().optional(),
  route: z.enum(DRIVER_ROUTES).optional(),
  flag: z.enum(['all', 'normal', 'short']).default('all'),
});

router.get('/trips', requireAuth('driver'), async (req, res, next) => {
  try {
    const query = tripHistoryQuerySchema.parse(req.query);

    const where = {
      driverId: req.auth!.sub,
      status: 'COMPLETED' as const,
      ...(query.dateFrom || query.dateTo
        ? { startedAt: { ...(query.dateFrom ? { gte: query.dateFrom } : {}), ...(query.dateTo ? { lt: query.dateTo } : {}) } }
        : {}),
      ...(query.route ? { route: query.route } : {}),
      ...(query.flag === 'short' ? { isShortTrip: true } : query.flag === 'normal' ? { isShortTrip: false } : {}),
    };

    const [trips, totalTrips] = await Promise.all([
      prisma.trip.findMany({
        where,
        orderBy: { startedAt: 'desc' },
        skip: (query.page - 1) * query.limit,
        take: query.limit,
      }),
      prisma.trip.count({ where }),
    ]);

    const totalPages = Math.max(1, Math.ceil(totalTrips / query.limit));

    res.json({
      trips: trips.map(toPublicTrip),
      currentPage: query.page,
      pageSize: query.limit,
      totalTrips,
      totalPages,
      hasNextPage: query.page < totalPages,
      routes: DRIVER_ROUTES,
    });
  } catch (err) {
    next(err);
  }
});

// Single-trip lookup, scoped to the calling driver — backs
// DriverTripDetailsScreen/DriverTripExplanationScreen's own polling (an
// admin can review this exact trip while the driver is sitting on one of
// those screens) and the notifications screen's "open the trip this
// notification points at" navigation. Replaces the old pattern of
// re-syncing this driver's *entire* trip history just to refresh or look
// up one trip by id — the whole reason Trip History is paginated now is
// that a full sync doesn't scale, so nothing else should do one either.
router.get('/trips/:id', requireAuth('driver'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const trip = await prisma.trip.findUnique({ where: { id } });
    if (!trip || trip.driverId !== req.auth!.sub) {
      res.status(404).json({ error: 'Trip not found.' });
      return;
    }
    res.json({ trip: toPublicTrip(trip) });
  } catch (err) {
    next(err);
  }
});

const submitExplanationSchema = z.object({
  explanation: z.string().trim().min(1, 'Explanation cannot be empty.').max(1000),
});

// A driver explaining why one of their own trips came in under the
// short-trip threshold. Resubmittable (each call overwrites the previous
// explanation + explanationSubmittedAt) so a driver can correct/expand
// it, but only for a trip that (a) is actually theirs — checked below,
// same as /trips/:id/end and /trips/:id/location, (b) was actually
// flagged, and (c) hasn't been reviewed yet — once an admin has acted on
// it, the explanation that call was based on is locked, so the app's own
// "Update Explanation" button being disabled can't be bypassed by calling
// this directly. Nothing here is writable by the driver besides the
// explanation text itself (isShortTrip, flagReason, reviewStatus,
// reviewedAt, adminReviewNote all stay admin/backend-only, see PATCH
// /api/admin/trips/:id/review).
router.patch('/trips/:id/explanation', requireAuth('driver'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = submitExplanationSchema.parse(req.body);

    const trip = await prisma.trip.findUnique({ where: { id } });
    if (!trip || trip.driverId !== req.auth!.sub) {
      res.status(404).json({ error: 'Trip not found.' });
      return;
    }
    if (!trip.isShortTrip) {
      res.status(400).json({ error: 'This trip was not flagged, so there is nothing to explain.' });
      return;
    }
    if (trip.reviewStatus !== 'PENDING') {
      res.status(400).json({ error: 'This trip has already been reviewed and can no longer be explained.' });
      return;
    }

    const updated = await prisma.trip.update({
      where: { id },
      data: { driverExplanation: body.explanation, explanationSubmittedAt: new Date() },
    });

    // Lets admins know there's something to review without having to poll
    // every driver's Trip History for one — mirrors the other ADMIN
    // notifications in this app (see e.g. "New severe complaint filed" in
    // commuter.ts). The driver record is only needed for this message; no
    // need to require it earlier since a missing driver here would mean
    // req.auth's own token no longer resolves, which requireAuth already
    // guards against.
    const driver = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
    await notifyAdmin({
      title: 'Driver explanation submitted',
      message: `${driver?.fullName ?? 'A driver'} (${driver?.plateNumber ?? '—'}) explained their short trip on ${updated.route ?? 'an unnamed route'} — needs review.`,
      type: 'TRIP_EXPLANATION_SUBMITTED',
      referenceId: req.auth!.sub,
    });

    res.json({ trip: toPublicTrip(updated) });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// DAYS NOT OPERATED — whether a driver operated on a day is read from their
// real trips; this only records a *reason* for a past/current day with no
// trip at all, and only if the reporting workflow is in use.
// ---------------------------------------------------------------------------
const nonOperationSchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be YYYY-MM-DD'),
  reason: z.string().trim().min(3, 'Please give a short reason.').max(500),
});

router.put('/non-operation', requireAuth('driver'), async (req, res, next) => {
  try {
    const body = nonOperationSchema.parse(req.body);
    const today = manilaDayKey(new Date());
    if (body.date > today) {
      res.status(400).json({ error: "You can't give a reason for a day that hasn't happened yet." });
      return;
    }
    const start = manilaMidnight(body.date);
    const tripThatDay = await prisma.trip.findFirst({
      where: { driverId: req.auth!.sub, startedAt: { gte: start, lt: new Date(start.getTime() + 86_400_000) } },
      select: { id: true },
    });
    if (tripThatDay) {
      res.status(409).json({ error: 'You have a trip recorded on that day, so it counts as a day you operated.' });
      return;
    }
    const date = new Date(`${body.date}T00:00:00Z`);
    const row = await prisma.driverNonOperationDay.upsert({
      where: { driverId_date: { driverId: req.auth!.sub, date } },
      create: { driverId: req.auth!.sub, date, reason: body.reason },
      update: { reason: body.reason },
    });
    res.json({ date: body.date, reason: row.reason });
  } catch (err) {
    next(err);
  }
});

router.get('/non-operation', requireAuth('driver'), async (req, res, next) => {
  try {
    const rows = await prisma.driverNonOperationDay.findMany({
      where: { driverId: req.auth!.sub },
      orderBy: { date: 'desc' },
      take: 60,
    });
    res.json({ days: rows.map((r) => ({ date: formatDateOnly(r.date), reason: r.reason })) });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// SHORT-TRIPPING INCIDENTS — the driver's side: see incidents raised against
// them and explain. They can never edit status, delete, or touch anything
// except their own explanation text (and only until a reviewer decides).
// ---------------------------------------------------------------------------
function toDriverIncident(i: {
  id: string;
  tripId: string | null;
  route: string | null;
  intendedDestination: string | null;
  occurredAt: Date;
  description: string | null;
  status: string;
  explanation: string | null;
  explanationSubmittedAt: Date | null;
  reviewNote: string | null;
}) {
  return {
    id: i.id,
    tripId: i.tripId,
    route: i.route,
    intendedDestination: i.intendedDestination,
    occurredAt: i.occurredAt,
    description: i.description,
    status: i.status,
    explanation: i.explanation,
    explanationSubmittedAt: i.explanationSubmittedAt,
    reviewNote: i.status === 'CONFIRMED' || i.status === 'DISMISSED' ? i.reviewNote : null,
    needsExplanation: i.status === 'PENDING_EXPLANATION',
    canExplain: ['PENDING_EXPLANATION', 'EXPLAINED', 'UNDER_REVIEW'].includes(i.status),
  };
}

router.get('/short-trip-incidents', requireAuth('driver'), async (req, res, next) => {
  try {
    const incidents = await prisma.shortTripIncident.findMany({
      where: { driverId: req.auth!.sub, status: { not: 'DUPLICATE' } },
      orderBy: { occurredAt: 'desc' },
      take: 50,
    });
    res.json({ incidents: incidents.map(toDriverIncident) });
  } catch (err) {
    next(err);
  }
});

const incidentExplanationSchema = z.object({
  explanation: z.string().trim().min(5, 'Please explain what happened (at least a few words).').max(2000),
});

router.patch('/short-trip-incidents/:id/explanation', requireAuth('driver'), async (req, res, next) => {
  try {
    const id: string = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const body = incidentExplanationSchema.parse(req.body);

    const incident = await prisma.shortTripIncident.findUnique({ where: { id } });
    if (!incident || incident.driverId !== req.auth!.sub) {
      res.status(404).json({ error: 'Incident not found.' });
      return;
    }
    if (!['PENDING_EXPLANATION', 'EXPLAINED', 'UNDER_REVIEW'].includes(incident.status)) {
      res.status(409).json({ error: 'This incident has already been decided and can no longer be explained.' });
      return;
    }

    const updated = await prisma.shortTripIncident.update({
      where: { id },
      data: {
        explanation: body.explanation,
        explanationSubmittedAt: new Date(),
        status: incident.status === 'PENDING_EXPLANATION' ? 'EXPLAINED' : incident.status,
      },
    });
    const driver = await prisma.driver.findUnique({ where: { id: req.auth!.sub }, select: { fullName: true, plateNumber: true } });
    await notifyAdmin({
      title: 'Short-tripping explanation submitted',
      message: `${driver?.fullName ?? 'A driver'} explained a short-tripping report — needs review.`,
      type: 'SHORT_TRIP_INCIDENT',
      referenceId: req.auth!.sub,
    });
    res.json({ incident: toDriverIncident(updated) });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// QR CODE
// ---------------------------------------------------------------------------
// The QR a driver shows encodes this opaque token, not their driverId
// directly — anyone can forge a QR that *contains* a plausible-looking
// "DR-00001", but only the backend can hand out a token that verify-qr
// below will actually recognize. It's assigned once at account creation
// and never changes — permanent for the life of the account, no
// self-serve rotation.

router.get('/me/qr-token', requireAuth('driver'), async (req, res, next) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
    if (!driver) {
      res.status(404).json({ error: 'Account not found.' });
      return;
    }

    // Every driver gets a qrToken at creation now, but this covers
    // accounts created before that was true (nothing to backfill).
    let { qrToken } = driver;
    if (!qrToken) {
      qrToken = await generateQrToken();
      await prisma.driver.update({ where: { id: driver.id }, data: { qrToken } });
    }

    res.json({ qrToken });
  } catch (err) {
    next(err);
  }
});

// Public on purpose — a commuter scanning a driver's QR isn't authenticated
// as anyone. Deliberately a narrower shape than toPublicDriver (which also
// carries mobileNumber/dateOfBirth for the driver's own authenticated
// /me-style views) — only what's safe to show a commuter before/while
// boarding: name, driverId, plate, profile photo, and the driver's live
// average rating (see Rating's doc comment in schema.prisma) — never the
// mobile number or date of birth.
router.get('/verify-qr/:token', async (req, res, next) => {
  try {
    const driver = await prisma.driver.findUnique({ where: { qrToken: req.params.token } });
    if (!driver) {
      res.status(404).json({ error: 'This QR code is not recognized.' });
      return;
    }

    const ratingInfo = await prisma.rating.aggregate({
      where: { driverId: driver.id },
      _avg: { stars: true },
      _count: { stars: true },
    });

    res.json({
      driver: {
        id: driver.id,
        driverId: driver.driverId,
        fullName: driver.fullName,
        plateNumber: driver.plateNumber,
        photoUrl: driver.photoUrl,
        averageRating: ratingInfo._avg.stars,
        ratingCount: ratingInfo._count.stars,
      },
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// DEMAND SIGNALS — the driver-side read of the same raw pings admin's
// Passenger Live Map uses (see GET /admin/demand-signals and
// DemandSignal's doc comment in schema.prisma). Clustered into grid cells
// client-side, same as the admin website's copy of that logic, so a
// driver sees the same "where passengers are waiting" clusters admin does
// from the same underlying data.
// ---------------------------------------------------------------------------

// Same window and reasoning as GET /admin/demand-signals — kept in sync
// deliberately so admin and driver never disagree on what counts as "still
// live."
const DEMAND_SIGNAL_WINDOW_MS = 5 * 60 * 1000;

const driverDemandSignalsQuerySchema = z.object({
  // The route this driver is currently running — when given, only pings
  // from commuters who picked the same route are returned, so a driver
  // running Pasig -> Quiapo doesn't get shown someone waiting for the
  // opposite direction. Omitted (e.g. before a route is chosen on the
  // dashboard) means "show everything."
  route: z.string().trim().min(1).optional(),
});

router.get('/demand-signals', requireAuth('driver'), async (req, res, next) => {
  try {
    const query = driverDemandSignalsQuerySchema.parse(req.query);
    const since = new Date(Date.now() - DEMAND_SIGNAL_WINDOW_MS);
    const signals = await prisma.demandSignal.findMany({
      // fulfilledAt: null — a commuter who's already boarded no longer
      // needs a pickup, so their signal stops showing here (see
      // fulfilledAt's doc comment in schema.prisma) even though it's kept
      // in the table.
      where: {
        createdAt: { gte: since },
        fulfilledAt: null,
        ...(query.route ? { route: query.route } : {}),
      },
      orderBy: { createdAt: 'desc' },
      select: { id: true, lat: true, lng: true, createdAt: true, partySize: true },
    });
    res.json({ signals });
  } catch (err) {
    next(err);
  }
});

const routeToPassengerQuerySchema = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
  passengerLat: z.coerce.number().min(-90).max(90),
  passengerLng: z.coerce.number().min(-180).max(180),
});

// Called once, on tap — not polled — when a driver taps a waiting-
// passenger cluster on the map. Real routed distance/duration (see
// lib/routingService.ts) when available, falling back to the same
// straight-line estimate GET /commuter/nearby-jeepneys uses (see
// utils/geo.ts) otherwise. No traffic condition here — not part of
// what the driver-side view needs to show.
router.get('/route-to-passenger', requireAuth('driver'), async (req, res, next) => {
  try {
    const query = routeToPassengerQuerySchema.parse(req.query);
    const from = { lat: query.lat, lng: query.lng };
    const to = { lat: query.passengerLat, lng: query.passengerLng };
    const routed = await getRoute(from, to);

    const distance = routed ? routed.distanceMeters : distanceMeters(from.lat, from.lng, to.lat, to.lng);
    const etaMinutes = routed ? Math.max(1, Math.round(routed.durationSeconds / 60)) : estimateEtaMinutes(distance);

    res.json({ distanceMeters: Math.round(distance), etaMinutes });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// DAILY OPERATIONS LOG — backs the Daily Operations / Weekly / Monthly
// Analytics screens (see DriverDailyLog's doc comment in schema.prisma).
// The app already has a local (SharedPreferences) version of this; these
// endpoints let it sync instead of being the sole source of truth.
// ---------------------------------------------------------------------------

// "Today" is the Asia/Manila calendar day — this app's audience and every
// driver's own idea of "today" — regardless of what timezone the server
// process happens to run in (a UTC host would otherwise roll "today" over at
// 8 AM Manila time, filing a driver's morning entries under yesterday).
// Returned as UTC midnight of that calendar day so it round-trips losslessly
// through DriverDailyLog.date, a `@db.Date` column: Prisma extracts a Date
// object's UTC calendar components when writing one, and a plain local-
// midnight Date is one UTC day *earlier* than intended for any positive
// UTC offset (PH is UTC+8) — the exact class of bug `dateOnly` in
// utils/date.ts already exists to avoid for dateOfBirth. Confirmed live:
// this used to store "today's" log under yesterday's date every time.
function todayDateOnly(): Date {
  const [year, month, day] = manilaDayKey(new Date()).split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day));
}

function toPublicDailyLog(log: {
  id: string;
  date: Date;
  startOdo: number;
  endOdo: number;
  earnings: number;
  fuelExpense: number;
  otherExpenses: number;
}) {
  return {
    id: log.id,
    date: formatDateOnly(log.date),
    startOdo: log.startOdo,
    endOdo: log.endOdo,
    earnings: log.earnings,
    fuelExpense: log.fuelExpense,
    otherExpenses: log.otherExpenses,
  };
}

const dailyLogSchema = z.object({
  startOdo: z.number().min(0),
  endOdo: z.number().min(0),
  earnings: z.number().min(0),
  fuelExpense: z.number().min(0).default(0),
  otherExpenses: z.number().min(0).default(0),
});

// Always writes to *today's* row (the Asia/Manila calendar day — see
// todayDateOnly) — a driver can revise it as many times as they like before
// the day is over, never picks a date.
router.put('/daily-log', requireAuth('driver'), async (req, res, next) => {
  try {
    const body = dailyLogSchema.parse(req.body);
    if (body.endOdo < body.startOdo) {
      res.status(400).json({ error: 'End odometer must be at least the start odometer.' });
      return;
    }

    const date = todayDateOnly();
    const log = await prisma.driverDailyLog.upsert({
      where: { driverId_date: { driverId: req.auth!.sub, date } },
      update: body,
      create: { driverId: req.auth!.sub, date, ...body },
    });

    res.json({ dailyLog: toPublicDailyLog(log) });
  } catch (err) {
    next(err);
  }
});

const dailyLogQuerySchema = z.object({
  days: z.coerce.number().int().min(1).max(366).default(31),
});

router.get('/daily-log', requireAuth('driver'), async (req, res, next) => {
  try {
    const query = dailyLogQuerySchema.parse(req.query);
    // UTC-constructed from the Manila calendar day, same reasoning as
    // todayDateOnly() above — filters a `@db.Date` column, so a plain
    // local-midnight Date would cut the window off one day too early.
    const since = todayDateOnly();
    since.setUTCDate(since.getUTCDate() - query.days);

    const logs = await prisma.driverDailyLog.findMany({
      where: { driverId: req.auth!.sub, date: { gte: since } },
      orderBy: { date: 'desc' },
    });

    res.json({ dailyLogs: logs.map(toPublicDailyLog) });
  } catch (err) {
    next(err);
  }
});

router.get('/today-stats', requireAuth('driver'), async (req, res, next) => {
  try {
    // Manila midnight, so the trip count and the daily log below agree on
    // what "today" means (see todayDateOnly).
    const today = todayDateOnly();
    const startOfToday = manilaMidnight(formatDateOnly(today));

    const [tripsToday, todayLog, firstTripToday] = await Promise.all([
      prisma.trip.count({ where: { driverId: req.auth!.sub, startedAt: { gte: startOfToday } } }),
      prisma.driverDailyLog.findUnique({
        where: { driverId_date: { driverId: req.auth!.sub, date: today } },
      }),
      // The odometer the driver entered at the start of today's first trip —
      // pre-fills "Start (km)" on the Daily Operations screen.
      prisma.trip.findFirst({
        where: { driverId: req.auth!.sub, startedAt: { gte: startOfToday }, startingOdometer: { not: null } },
        orderBy: { startedAt: 'asc' },
        select: { startingOdometer: true },
      }),
    ]);

    // Net income = what the driver took in minus what they logged spending
    // (fuel + other expenses) — the same formula the admin Operations Report
    // uses (see GET /admin/operations-report), so both dashboards agree. No
    // expense is ever assumed: an expense the driver hasn't logged is 0, not
    // an estimate. No log at all yet today means there's nothing to net, so
    // it stays null rather than reading as a real ₱0.
    const earnings = todayLog?.earnings ?? null;
    const fuelExpense = todayLog?.fuelExpense ?? 0;
    const otherExpenses = todayLog?.otherExpenses ?? 0;

    res.json({
      tripsToday,
      startingOdometerToday: firstTripToday?.startingOdometer ?? null,
      // Gross — kept for anything still reading it; the dashboard's
      // "Earnings Today" card now shows netIncomeToday instead.
      earningsToday: earnings,
      fuelExpenseToday: todayLog ? fuelExpense : null,
      otherExpensesToday: todayLog ? otherExpenses : null,
      netIncomeToday: earnings === null ? null : earnings - fuelExpense - otherExpenses,
    });
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// NOTIFICATIONS — server-triggered async events (see Notification's doc
// comment in schema.prisma), merged client-side with each app's own local
// notifications.
// ---------------------------------------------------------------------------

const notificationsQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(50),
});

router.get('/notifications', requireAuth('driver'), async (req, res, next) => {
  try {
    const query = notificationsQuerySchema.parse(req.query);
    const where = { recipientId: req.auth!.sub };
    const [notifications, totalNotifications] = await Promise.all([
      prisma.driverNotification.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (query.page - 1) * query.pageSize,
        take: query.pageSize,
      }),
      prisma.driverNotification.count({ where }),
    ]);
    const totalPages = Math.max(1, Math.ceil(totalNotifications / query.pageSize));
    res.json({
      notifications,
      currentPage: query.page,
      pageSize: query.pageSize,
      totalNotifications,
      totalPages,
      hasNextPage: query.page < totalPages,
    });
  } catch (err) {
    next(err);
  }
});

router.post('/notifications/mark-read', requireAuth('driver'), async (req, res, next) => {
  try {
    await prisma.driverNotification.updateMany({
      where: { recipientId: req.auth!.sub, isRead: false },
      data: { isRead: true },
    });
    res.json({ message: 'Marked read.' });
  } catch (err) {
    next(err);
  }
});

// "Clear All" — a real delete, not a soft-dismiss; there's no undo, same
// as the commuter app's own DELETE /notifications. Only ever clears this
// driver's own notifications (recipientId scoped), never anyone else's.
router.delete('/notifications', requireAuth('driver'), async (req, res, next) => {
  try {
    await prisma.driverNotification.deleteMany({ where: { recipientId: req.auth!.sub } });
    res.json({ message: 'Notifications cleared.' });
  } catch (err) {
    next(err);
  }
});

export default router;
