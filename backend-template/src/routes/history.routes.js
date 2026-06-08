// History routes (protected). Written via PUT /progress; entries removable here.
import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';

const router = Router();
router.use(requireAuth);

const idSchema = z.string().min(1).max(64);

// GET /history?limit=50
router.get(
  '/',
  validate({ query: z.object({ limit: z.coerce.number().int().min(1).max(200).default(50) }) }),
  async (req, res, next) => {
    try {
      const rows = await prisma.history.findMany({
        where: { userId: req.user.id },
        orderBy: { lastReadAt: 'desc' },
        take: req.query.limit,
      });
      return res.json({ history: rows });
    } catch (err) {
      return next(err);
    }
  },
);

// DELETE /history/:mangaId - remove one manga from the user's history.
router.delete(
  '/:mangaId',
  validate({ params: z.object({ mangaId: idSchema }) }),
  async (req, res, next) => {
    try {
      await prisma.history.deleteMany({
        where: { userId: req.user.id, mangaId: req.params.mangaId },
      });
      return res.status(204).send();
    } catch (err) {
      return next(err);
    }
  },
);

export default router;
