import type { AuthTokenPayload } from '../utils/jwt';

declare global {
  namespace Express {
    interface Request {
      auth?: AuthTokenPayload;
      /** Set by requireStaff: the calling admin account and its business role. */
      staff?: { id: string; role: import('@prisma/client').AdminRole };
    }
  }
}

export {};
