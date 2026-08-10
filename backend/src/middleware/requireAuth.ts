import type { NextFunction, Request, Response } from 'express';
import { verifyAuthToken, type AuthTokenPayload, type Role } from '../lib/jwt';
import { ApiError } from '../lib/errors';

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      auth?: AuthTokenPayload;
    }
  }
}

export function requireAuth(role?: Role) {
  return (req: Request, res: Response, next: NextFunction) => {
    const header = req.headers.authorization;
    const token = header?.startsWith('Bearer ') ? header.slice('Bearer '.length) : undefined;

    if (!token) {
      next(new ApiError(401, 'unauthorized', 'Missing bearer token'));
      return;
    }

    try {
      const payload = verifyAuthToken(token);
      if (role && payload.role !== role) {
        next(new ApiError(403, 'forbidden', `This endpoint is for ${role}s only`));
        return;
      }
      req.auth = payload;
      next();
    } catch {
      next(new ApiError(401, 'unauthorized', 'Invalid or expired token'));
    }
  };
}
