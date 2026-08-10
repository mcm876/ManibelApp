import { prisma } from './prisma';
import type { OtpPurpose } from '@prisma/client';

const OTP_TTL_MINUTES = 5;

function generateCode(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

/**
 * Creates a fresh OTP and "sends" it. There's no SMS gateway wired up yet,
 * so for local dev the code is just logged to the server console — swap
 * this out for a real SMS provider before shipping.
 */
export async function issueOtp(mobileNumber: string, purpose: OtpPurpose): Promise<void> {
  const code = generateCode();
  const expiresAt = new Date(Date.now() + OTP_TTL_MINUTES * 60 * 1000);

  await prisma.otpCode.create({
    data: { mobileNumber, purpose, code, expiresAt },
  });

  // eslint-disable-next-line no-console
  console.log(`[OTP] ${purpose} code for ${mobileNumber}: ${code} (expires in ${OTP_TTL_MINUTES}m)`);
}

/**
 * Verifies a code against the most recent unconsumed OTP issued for
 * (mobileNumber, purpose). Consumes it on success so it can't be replayed.
 */
export async function verifyOtp(
  mobileNumber: string,
  purpose: OtpPurpose,
  code: string,
): Promise<boolean> {
  const otp = await prisma.otpCode.findFirst({
    where: { mobileNumber, purpose, consumed: false },
    orderBy: { createdAt: 'desc' },
  });

  if (!otp || otp.expiresAt < new Date() || otp.code !== code) {
    return false;
  }

  await prisma.otpCode.update({
    where: { id: otp.id },
    data: { consumed: true },
  });

  return true;
}
