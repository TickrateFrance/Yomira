// Auth middleware: require a valid Bearer JWT, attach req.user.
import { verifyToken } from '../utils/jwt.js';

export function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');

  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ error: 'Missing or malformed Authorization header' });
  }

  try {
    const decoded = verifyToken(token);
    if (!decoded.sub) {
      return res.status(401).json({ error: 'Invalid or expired token' });
    }
    req.user = { id: decoded.sub, username: decoded.username };
    return next();
  } catch {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}
