// Library/favorites routes (all protected).
import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';

const router = Router();
router.use(requireAuth);

const idSchema = z.string().min(1).max(64);

// GET /library
router.get('/', async (req, res, next) => {
  try {
    const rows = await prisma.library.findMany({
      where: { userId: req.user.id },
      orderBy: { addedAt: 'desc' },
    });
    return res.json({ library: rows });
  } catch (err) {
    return next(err);
  }
});

// POST /library  { mangaId }
router.post('/', validate({ body: z.object({ mangaId: idSchema }) }), async (req, res, next) => {
  try {
    const { mangaId } = req.body;
    const item = await prisma.library.upsert({
      where: { userId_mangaId: { userId: req.user.id, mangaId } },
      create: { userId: req.user.id, mangaId },
      update: {}, // already present = no-op (idempotent)
    });
    return res.status(201).json({ item });
  } catch (err) {
    return next(err);
  }
});

// DELETE /library/:mangaId
router.delete('/:mangaId', validate({ params: z.object({ mangaId: idSchema }) }), async (req, res, next) => {
  try {
    await prisma.library.deleteMany({
      where: { userId: req.user.id, mangaId: req.params.mangaId },
    });
    return res.status(204).send();
  } catch (err) {
    return next(err);
  }
});

export default router;
