// GET /api/v1/app-status - compares the caller's version against the DB row for
// its platform. Public (no auth, no version gate) so a forced client can still
// read the update URL.
import { Router } from 'express';
import { prisma } from '../lib/prisma.js';
import { compareVersions } from '../utils/version.js';

const router = Router();

router.get('/', async (req, res, next) => {
  try {
    const platform = req.header('X-Platform');
    const version = req.header('X-App-Version');
    if (!platform || !version) return res.json({ status: 'none', url: '' });

    const row = await prisma.appVersion.findUnique({ where: { platform } });
    if (!row) return res.json({ status: 'none', url: '' });

    let status = 'none';
    if (compareVersions(version, row.minRequiredVersion) < 0) status = 'force';
    else if (compareVersions(version, row.latestVersion) < 0) status = 'soft';

    return res.json({ status, url: row.url });
  } catch (err) {
    return next(err);
  }
});

export default router;
