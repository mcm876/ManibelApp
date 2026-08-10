import jwt, { type SignOptions } from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET) {
  throw new Error('JWT_SECRET is not set. Copy .env.example to .env and set it.');
}

const JWT_EXPIRES_IN = (process.env.JWT_EXPIRES_IN ?? '7d') as SignOptions['expiresIn'];

export type Role = 'commuter' | 'driver';

export interface AuthTokenPayload {
  sub: string;
  role: Role;
}

export function signAuthToken(payload: AuthTokenPayload): string {
  return jwt.sign(payload, JWT_SECRET as string, { expiresIn: JWT_EXPIRES_IN });
}

export function verifyAuthToken(token: string): AuthTokenPayload {
  const payload = jwt.verify(token, JWT_SECRET as string) as jwt.JwtPayload;
  if (payload.purpose === 'password_reset') {
    throw new Error('Not an auth token');
  }
  return payload as unknown as AuthTokenPayload;
}

export interface ResetTokenPayload {
  sub: string;
  role: Role;
  purpose: 'password_reset';
}

/** Short-lived token proving OTP ownership, exchanged for a real password reset. */
export function signResetToken(payload: Omit<ResetTokenPayload, 'purpose'>): string {
  return jwt.sign({ ...payload, purpose: 'password_reset' }, JWT_SECRET as string, {
    expiresIn: '10m',
  });
}

export function verifyResetToken(token: string): ResetTokenPayload {
  const payload = jwt.verify(token, JWT_SECRET as string) as jwt.JwtPayload;
  if (payload.purpose !== 'password_reset') {
    throw new Error('Not a reset token');
  }
  return payload as unknown as ResetTokenPayload;
}
