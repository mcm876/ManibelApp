import crypto from 'node:crypto';
import type { NextFunction, Request, Response } from 'express';
import { ApiError } from '../lib/errors';

/**
 * Guards admin endpoints with a shared secret sent as `x-admin-key`. There
 * is no admin account model, so ADMIN_API_KEY in .env is the credential; if
 * it isn't set the admin API is disabled rather than left open.
 */
export function requireAdmin(req: Request, _res: Response, next: NextFunction) {
  const expected = process.env.ADMIN_API_KEY;
  if (!expected) {
    next(new ApiError(503, 'admin_disabled', 'Admin API is not configured (set ADMIN_API_KEY)'));
    return;
  }

  const provided = req.header('x-admin-key') ?? '';
  const a = crypto.createHash('sha256').update(provided).digest();
  const b = crypto.createHash('sha256').update(expected).digest();
  if (!crypto.timingSafeEqual(a, b)) {
    next(new ApiError(401, 'unauthorized', 'Invalid admin key'));
    return;
  }
  next();
}
