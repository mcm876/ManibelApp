import { z } from 'zod';

/**
 * Mirrors _validatePassword in
 * lib/features/auth/screens/commuter_signup_screen.dart, so the API
 * enforces the same policy the Flutter form does instead of trusting the
 * client. Keep these two in sync.
 */
export const passwordSchema = z
  .string()
  .min(8, 'Password must be at least 8 characters')
  .refine((v) => !v.includes(' '), 'Password cannot contain spaces')
  .refine((v) => /[A-Z]/.test(v), 'Password must include an uppercase letter')
  .refine((v) => /[a-z]/.test(v), 'Password must include a lowercase letter')
  .refine((v) => /\d/.test(v), 'Password must include a number')
  .refine((v) => /[^A-Za-z0-9]/.test(v), 'Password must include a special character');

export const mobileNumberSchema = z
  .string()
  .min(1, 'Mobile number is required');

export const otpCodeSchema = z
  .string()
  .length(6, 'Enter the 6-digit code');

export const commuterSignupSchema = z.object({
  fullName: z.string().trim().min(1, 'Full name is required'),
  mobileNumber: mobileNumberSchema,
  password: passwordSchema,
  dateOfBirth: z.coerce.date().optional(),
});

export const loginSchema = z.object({
  mobileNumber: mobileNumberSchema,
  password: z.string().min(1, 'Password is required'),
});

export const verifyOtpSchema = z.object({
  mobileNumber: mobileNumberSchema,
  code: otpCodeSchema,
});

export const forgotPasswordSchema = z.object({
  mobileNumber: mobileNumberSchema,
});

export const resetPasswordSchema = z.object({
  resetToken: z.string().min(1),
  newPassword: passwordSchema,
});
