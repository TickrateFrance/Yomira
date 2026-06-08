// Express app entrypoint (blank template).
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import morgan from 'morgan';

import { env } from './config/env.js';
import { prisma, disconnectPrisma } from './lib/prisma.js';
import { notFound, errorHandler } from './middleware/error.js';
import { versionGate } from './middleware/version-gate.js';

import appStatusRoutes from './routes/appstatus.routes.js';
import authRoutes from './routes/auth.routes.js';
import progressRoutes from './routes/progress.routes.js';
import libraryRoutes from './routes/library.routes.js';
import historyRoutes from './routes/history.routes.js';

const app = express();
// Behind a reverse proxy: trust one proxy hop so req.ip is the real client.
app.set('trust proxy', 1);

app.use(helmet());
app.use(
  cors({
    origin: env.corsOrigins, // '*' or string[]
  }),
);
app.use(express.json({ limit: '64kb' }));
// 'tiny' logs method/url/status/time only - no bodies, no secrets.
app.use(morgan('tiny'));

// Liveness/readiness probe.
app.get('/health', async (req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ status: 'ok' });
  } catch {
    res.status(503).json({ status: 'db-unavailable' });
  }
});

// Public + ungated: the app must read status/url even when force-updated.
app.use('/api/v1/app-status', appStatusRoutes);

// Gate everything below: 426 if the client is older than the platform minimum.
app.use(versionGate);

app.use('/auth', authRoutes);
app.use('/progress', progressRoutes);
app.use('/library', libraryRoutes);
app.use('/history', historyRoutes);

app.use(notFound);
app.use(errorHandler);

const server = app.listen(env.PORT, () => {
  console.log(`Backend listening on :${env.PORT}`);
});

// Graceful shutdown.
async function shutdown(signal) {
  console.log(`${signal} received, shutting down...`);
  server.close(async () => {
    await disconnectPrisma();
    process.exit(0);
  });
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
