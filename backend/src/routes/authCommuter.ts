import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { prisma } from '../lib/prisma';
import { toE164 } from '../lib/phone';
import { issueOtp, verifyOtp } from '../lib/otp';
import { signAuthToken, signResetToken, verifyResetToken } from '../lib/jwt';
import { generateCommuterId } from '../lib/ids';
import { ApiError } from '../lib/errors';
import { asyncHandler } from '../lib/asyncHandler';
import { requireAuth } from '../middleware/requireAuth';
import { validateBody } from '../middleware/validate';
import {
  commuterSignupSchema,
  forgotPasswordSchema,
  loginSchema,
  resetPasswordSchema,
  verifyOtpSchema,
} from '../lib/validation';

const BCRYPT_ROUNDS = 10;

function toPublicCommuter(commuter: {
  commuterId: string;
  fullName: string;
  mobileNumber: string;
  dateOfBirth: Date | null;
  photoUrl: string | null;
}) {
  return {
    commuterId: commuter.commuterId,
    fullName: commuter.fullName,
    mobileNumber: commuter.mobileNumber,
    dateOfBirth: commuter.dateOfBirth,
    photoUrl: commuter.photoUrl,
  };
}

export const authCommuterRouter = Router();

/**
 * No phone-OTP gate here — in the client, the screen right after signup is
 * CommuterVerificationScreen (government ID + face verification), not an
 * OTP entry screen. So the account is usable immediately and this returns
 * a session token straight away, same as /login.
 */
authCommuterRouter.post(
  '/signup',
  validateBody(commuterSignupSchema),
  asyncHandler(async (req, res) => {
    const { fullName, password, dateOfBirth } = req.body as {
      fullName: string;
      password: string;
      dateOfBirth?: Date;
    };
    const mobileNumber = toE164((req.body as { mobileNumber: string }).mobileNumber);

    const existing = await prisma.commuter.findUnique({ where: { mobileNumber } });
    if (existing) {
      throw new ApiError(409, 'mobile_already_registered', 'This mobile number is already registered');
    }

    const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);

    const commuter = await prisma.commuter.create({
      data: {
        commuterId: generateCommuterId(),
        fullName,
        mobileNumber,
        passwordHash,
        dateOfBirth,
      },
    });

    const token = signAuthToken({ sub: commuter.id, role: 'commuter' });
    res.status(201).json({ token, commuter: toPublicCommuter(commuter) });
  }),
);

authCommuterRouter.post(
  '/login',
  validateBody(loginSchema),
  asyncHandler(async (req, res) => {
    const mobileNumber = toE164((req.body as { mobileNumber: string }).mobileNumber);
    const { password } = req.body as { password: string };

    const commuter = await prisma.commuter.findUnique({ where: { mobileNumber } });
    if (!commuter || !(await bcrypt.compare(password, commuter.passwordHash))) {
      throw new ApiError(401, 'invalid_credentials', 'Incorrect mobile number or password');
    }

    const token = signAuthToken({ sub: commuter.id, role: 'commuter' });
    res.json({ token, commuter: toPublicCommuter(commuter) });
  }),
);

authCommuterRouter.post(
  '/forgot-password',
  validateBody(forgotPasswordSchema),
  asyncHandler(async (req, res) => {
    const mobileNumber = toE164((req.body as { mobileNumber: string }).mobileNumber);

    const commuter = await prisma.commuter.findUnique({ where: { mobileNumber } });
    if (!commuter) {
      throw new ApiError(404, 'not_found', 'This mobile number isn\'t registered');
    }

    await issueOtp(mobileNumber, 'PASSWORD_RESET');
    res.json({ mobileNumber, message: 'A reset code was sent to your mobile number.' });
  }),
);

authCommuterRouter.post(
  '/verify-reset-otp',
  validateBody(verifyOtpSchema),
  asyncHandler(async (req, res) => {
    const mobileNumber = toE164((req.body as { mobileNumber: string }).mobileNumber);
    const { code } = req.body as { code: string };

    const commuter = await prisma.commuter.findUnique({ where: { mobileNumber } });
    if (!commuter) {
      throw new ApiError(404, 'not_found', 'No account for this mobile number');
    }

    const ok = await verifyOtp(mobileNumber, 'PASSWORD_RESET', code);
    if (!ok) {
      throw new ApiError(400, 'invalid_otp', 'That code is invalid or expired');
    }

    const resetToken = signResetToken({ sub: commuter.id, role: 'commuter' });
    res.json({ resetToken });
  }),
);

authCommuterRouter.post(
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
    if (payload.role !== 'commuter') {
      throw new ApiError(403, 'forbidden', 'Wrong account type for this reset token');
    }

    const passwordHash = await bcrypt.hash(newPassword, BCRYPT_ROUNDS);
    await prisma.commuter.update({
      where: { id: payload.sub },
      data: { passwordHash },
    });

    res.json({ message: 'Password updated' });
  }),
);

authCommuterRouter.get(
  '/me',
  requireAuth('commuter'),
  asyncHandler(async (req, res) => {
    const commuter = await prisma.commuter.findUnique({ where: { id: req.auth!.sub } });
    if (!commuter) {
      throw new ApiError(404, 'not_found', 'Account no longer exists');
    }
    res.json({ commuter: toPublicCommuter(commuter) });
  }),
);
