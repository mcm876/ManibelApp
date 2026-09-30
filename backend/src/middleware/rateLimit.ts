import type { Request } from 'express';
import rateLimit, { ipKeyGenerator } from 'express-rate-limit';

import { verifyAuthToken } from '../utils/jwt';

/** The caller's real IP. Behind Cloudflare + Render, `req.ip` is a shared
 * Cloudflare edge address, so counting by it puts unrelated users (and one
 * person's two phones) in the same bucket; Cloudflare puts the real client
 * address in CF-Connecting-IP (and overwrites anything a client sends). */
function clientIp(req: Request): string {
  const header = req.headers['cf-connecting-ip'];
  const cf = (Array.isArray(header) ? header[0] : header)?.trim();
  return ipKeyGenerator(cf || req.ip || 'unknown');
}

/** The signed-in account behind a request, from a *verified* token — a
 * forged/expired one doesn't count, so it can't be used to dodge the limit. */
function authedSubject(req: Request): string | null {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) return null;
  try {
    return verifyAuthToken(header.slice(7)).sub;
  } catch {
    return null;
  }
}

/** Broad safety net over every /api route — generous enough that normal
 * app usage (polling, live maps, a driver's location pings every few seconds)
 * never comes close to it. Counted per signed-in account, so one user's
 * activity — or a busy shared address — can never lock someone else out of
 * logging in or ending a trip; requests with no valid token are counted per
 * real client IP. */
export const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: (req) => (authedSubject(req) ? 3000 : 600),
  keyGenerator: (req) => {
    const subject = authedSubject(req);
    return subject ? `user:${subject}` : `ip:${clientIp(req)}`;
  },
  standardHeaders: true,
  legacyHeaders: false,
});

/** Tighter limit for unauthenticated, brute-forceable endpoints — login,
 * signup, and OTP request/verify. Keyed by IP + request body's
 * mobileNumber (when present) so one IP can't lock out every account on
 * the device, but repeated attempts against a single number still get
 * throttled. */
export const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => {
    const mobileNumber = (req.body as { mobileNumber?: unknown } | undefined)?.mobileNumber;
    const ip = clientIp(req);
    return typeof mobileNumber === 'string' ? `${ip}:${mobileNumber}` : ip;
  },
});
