// Global gate: returns 426 Upgrade Required when the caller's X-App-Version is
// below the platform minimum. Mount AFTER /health and /api/v1/app-status so
// those stay reachable for a forced client.
import { prisma } from '../lib/prisma.js';
import { compareVersions } from '../utils/version.js';

const TTL = 60_000; // 60s in-memory cache of platform -> row
const cache = new Map();

async function getRow(platform) {
  const hit = cache.get(platform);
  if (hit && Date.now() - hit.t < TTL) return hit.row;
  const row = await prisma.appVersion.findUnique({ where: { platform } });
  cache.set(platform, { t: Date.now(), row });
  return row;
}

export function versionGate(req, res, next) {
  const platform = req.header('X-Platform');
  const version = req.header('X-App-Version');
  // Unknown clients (no headers) are not gated.
  if (!platform || !version) return next();

  getRow(platform)
    .then((row) => {
      if (row && compareVersions(version, row.minRequiredVersion) < 0) {
        return res.status(426).json({
          error: 'Upgrade Required',
          status: 'force',
          url: row.url,
        });
      }
      return next();
    })
    .catch(next);
}
