// Reading-progress routes (all protected). Upsert keyed by (user, chapter).
import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';

const router = Router();
router.use(requireAuth);

// IDs are opaque strings (e.g. MangaDex UUIDs); keep loose but bounded.
const idSchema = z.string().min(1).max(64);

const putSchema = z.object({
  mangaId: idSchema,
  chapterId: idSchema,
  lastPage: z.coerce.number().int().min(0).default(0),
  read: z.boolean().default(false),
  // Optional snapshot metadata so history/progress survive a reinstall.
  chapterNumber: z.string().max(32).optional(),
  language: z.string().max(16).optional(),
  title: z.string().max(512).optional(),
  coverUrl: z.string().max(2048).optional(),
});

// GET /progress  -> all progress for the user
router.get('/', async (req, res, next) => {
  try {
    const rows = await prisma.readingProgress.findMany({
      where: { userId: req.user.id },
      orderBy: { updatedAt: 'desc' },
    });
    return res.json({ progress: rows });
  } catch (err) {
    return next(err);
  }
});

// GET /progress/:mangaId -> progress for one manga
router.get('/:mangaId', validate({ params: z.object({ mangaId: idSchema }) }), async (req, res, next) => {
  try {
    const rows = await prisma.readingProgress.findMany({
      where: { userId: req.user.id, mangaId: req.params.mangaId },
      orderBy: { updatedAt: 'desc' },
    });
    return res.json({ progress: rows });
  } catch (err) {
    return next(err);
  }
});

// PUT /progress -> upsert one chapter's progress, bump history
router.put('/', validate({ body: putSchema }), async (req, res, next) => {
  try {
    const { mangaId, chapterId, lastPage, read, chapterNumber, language, title, coverUrl } =
      req.body;
    const userId = req.user.id;

    const [progress] = await prisma.$transaction([
      prisma.readingProgress.upsert({
        where: { userId_chapterId: { userId, chapterId } },
        create: { userId, mangaId, chapterId, lastPage, read, chapterNumber, language },
        update: { mangaId, lastPage, read, chapterNumber, language },
      }),
      prisma.history.upsert({
        where: { userId_mangaId: { userId, mangaId } },
        create: { userId, mangaId, title: title ?? '', coverUrl: coverUrl ?? '' },
        // Only overwrite the snapshot when the client actually sent one.
        update: {
          lastReadAt: new Date(),
          ...(title ? { title } : {}),
          ...(coverUrl ? { coverUrl } : {}),
        },
      }),
    ]);

    return res.json({ progress });
  } catch (err) {
    return next(err);
  }
});

export default router;
