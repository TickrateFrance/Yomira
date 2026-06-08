// Auth routes: register, login, verify, me.
import { Router } from 'express';
import bcrypt from 'bcrypt';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';
import { env } from '../config/env.js';
import { signToken } from '../utils/jwt.js';
import { validate } from '../middleware/validate.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();

const credentialsSchema = z.object({
  username: z
    .string()
    .trim()
    .min(3, 'username min 3 chars')
    .max(32, 'username max 32 chars')
    .regex(/^[a-zA-Z0-9_.-]+$/, 'username: letters, digits, _ . - only'),
  password: z.string().min(8, 'password min 8 chars').max(128, 'password max 128 chars'),
});

// POST /auth/register
router.post('/register', validate({ body: credentialsSchema }), async (req, res, next) => {
  try {
    const { username, password } = req.body;

    const existing = await prisma.user.findUnique({ where: { username } });
    if (existing) {
      return res.status(409).json({ error: 'Username already taken' });
    }

    const passwordHash = await bcrypt.hash(password, env.BCRYPT_ROUNDS);
    const user = await prisma.user.create({
      data: { username, passwordHash },
      select: { id: true, username: true, createdAt: true },
    });

    const token = signToken({ sub: user.id, username: user.username });
    return res.status(201).json({ token, user });
  } catch (err) {
    return next(err);
  }
});

// POST /auth/login
router.post('/login', validate({ body: credentialsSchema }), async (req, res, next) => {
  try {
    const { username, password } = req.body;

    const user = await prisma.user.findUnique({ where: { username } });
    // Constant-ish path: always run a compare to reduce username enumeration timing.
    const hash = user?.passwordHash || '$2b$12$invalidinvalidinvalidinvalidinvalidinvalidinv';
    const ok = await bcrypt.compare(password, hash);

    if (!user || !ok) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const token = signToken({ sub: user.id, username: user.username });
    return res.json({
      token,
      user: { id: user.id, username: user.username, createdAt: user.createdAt },
    });
  } catch (err) {
    return next(err);
  }
});

// /auth/verify - lightweight token check (e.g. for a reverse-proxy forward_auth).
// 200 = valid JWT, 401 = not (no DB hit). Accept any method.
router.all('/verify', requireAuth, (req, res) => res.json({ ok: true }));

// GET /auth/me
router.get('/me', requireAuth, async (req, res, next) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.user.id },
      select: { id: true, username: true, createdAt: true, updatedAt: true },
    });
    if (!user) return res.status(404).json({ error: 'User not found' });
    return res.json({ user });
  } catch (err) {
    return next(err);
  }
});

export default router;
