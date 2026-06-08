// JWT sign/verify wrappers.
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';

export function signToken(payload) {
  // payload kept minimal: { sub: userId, username }
  return jwt.sign(payload, env.JWT_SECRET, {
    expiresIn: env.JWT_EXPIRES_IN,
  });
}

export function verifyToken(token) {
  // Throws on invalid/expired; caller catches.
  return jwt.verify(token, env.JWT_SECRET);
}
