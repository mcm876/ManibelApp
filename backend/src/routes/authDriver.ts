import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { prisma } from '../lib/prisma';
import { toE164 } from '../lib/phone';
import { issueOtp, verifyOtp } from '../lib/otp';
import { signAuthToken, signResetToken, verifyResetToken } from '../lib/jwt';
import { ApiError } from '../lib/errors';
import { asyncHandler } from '../lib/asyncHandler';
import { requireAuth } from '../middleware/requireAuth';
import { validateBody } from '../middleware/validate';
import { forgotPasswordSchema, loginSchema, resetPasswordSchema, verifyOtpSchema } from '../lib/validation';

const BCRYPT_ROUNDS = 10;

function toPublicDriver(driver: {
  driverId: string;
  fullName: string;
  mobileNumber: string;
  plateNumber: string;
  photoUrl: string | null;
}) {
  return {
    driverId: driver.driverId,
    fullName: driver.fullName,
    mobileNumber: driver.mobileNumber,
    plateNumber: driver.plateNumber,
    photoUrl: driver.photoUrl,
  };
}

export const authDriverRouter = Router();

/**
 * Drivers don't self-register (see DriverSession.ensureDemoAccountSeeded in
 * the Flutter app) — accounts are provisioned out-of-band (admin/operator,
 * or `prisma/seed.ts` locally). This is login-only.
 */
authDriverRouter.post(
  '/login',
  validateBody(loginSchema),
  asyncHandler(async (req, res) => {
    const mobileNumber = toE164((req.body as { mobileNumber: string }).mobileNumber);
    const { password } = req.body as { password: string };

    const driver = await prisma.driver.findUnique({ where: { mobileNumber } });
    if (!driver || !(await bcrypt.compare(password, driver.passwordHash))) {
      throw new ApiError(401, 'invalid_credentials', 'Incorrect mobile number or password');
    }

    const token = signAuthToken({ sub: driver.id, role: 'driver' });
    res.json({ token, driver: toPublicDriver(driver) });
  }),
);

authDriverRouter.post(
  '/forgot-password',
  validateBody(forgotPasswordSchema),
  asyncHandler(async (req, res) => {
    const mobileNumber = toE164((req.body as { mobileNumber: string }).mobileNumber);

    const driver = await prisma.driver.findUnique({ where: { mobileNumber } });
    if (!driver) {
      throw new ApiError(404, 'not_found', 'This mobile number isn\'t registered');
    }

    await issueOtp(mobileNumber, 'PASSWORD_RESET');
    res.json({ mobileNumber, message: 'A reset code was sent to your mobile number.' });
  }),
);

authDriverRouter.post(
  '/verify-reset-otp',
  validateBody(verifyOtpSchema),
  asyncHandler(async (req, res) => {
    const mobileNumber = toE164((req.body as { mobileNumber: string }).mobileNumber);
    const { code } = req.body as { code: string };

    const driver = await prisma.driver.findUnique({ where: { mobileNumber } });
    if (!driver) {
      throw new ApiError(404, 'not_found', 'No account for this mobile number');
    }

    const ok = await verifyOtp(mobileNumber, 'PASSWORD_RESET', code);
    if (!ok) {
      throw new ApiError(400, 'invalid_otp', 'That code is invalid or expired');
    }

    const resetToken = signResetToken({ sub: driver.id, role: 'driver' });
    res.json({ resetToken });
  }),
);

authDriverRouter.post(
  '/reset-password',
  validateBody(resetPasswordSchema),
  asyncHandler(async (req, res) => {
    const { resetToken, newPassword } = req.body as { resetToken: string; newPassword: string };

    let payload;
    try {
      payload = verifyResetToken(resetToken);
    } catch {
      throw new ApiError(401, 'invalid_reset_token', 'This reset link has expired, request a new code');
    }
    if (payload.role !== 'driver') {
      throw new ApiError(403, 'forbidden', 'Wrong account type for this reset token');
    }

    const passwordHash = await bcrypt.hash(newPassword, BCRYPT_ROUNDS);
    await prisma.driver.update({
      where: { id: payload.sub },
      data: { passwordHash },
    });

    res.json({ message: 'Password updated' });
  }),
);

authDriverRouter.get(
  '/me',
  requireAuth('driver'),
  asyncHandler(async (req, res) => {
    const driver = await prisma.driver.findUnique({ where: { id: req.auth!.sub } });
    if (!driver) {
      throw new ApiError(404, 'not_found', 'Account no longer exists');
    }
    res.json({ driver: toPublicDriver(driver) });
  }),
);
