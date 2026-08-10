import express from 'express';
import cors from 'cors';
import { authCommuterRouter } from './routes/authCommuter';
import { authDriverRouter } from './routes/authDriver';
import { errorHandler, notFoundHandler } from './middleware/errorHandler';

export function createApp() {
  const app = express();

  app.use(cors());
  app.use(express.json());

  app.get('/health', (_req, res) => res.json({ ok: true }));

  app.use('/auth/commuter', authCommuterRouter);
  app.use('/auth/driver', authDriverRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
