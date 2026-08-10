import type { NextFunction, Request, Response } from 'express';
import { ApiError } from '../lib/errors';

// Express only treats a 4-arg function as an error handler, so all four
// params must stay even though `next` is unused.
// eslint-disable-next-line @typescript-eslint/no-unused-vars
export function errorHandler(err: unknown, req: Request, res: Response, next: NextFunction) {
  if (err instanceof ApiError) {
    res.status(err.status).json({ error: err.code, message: err.message });
    return;
  }

  console.error(err);
  res.status(500).json({ error: 'internal_error', message: 'Something went wrong' });
}

export function notFoundHandler(req: Request, res: Response) {
  res.status(404).json({ error: 'not_found', message: 'Route not found' });
}
