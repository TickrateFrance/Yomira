// 404 + central error handler.
export function notFound(req, res) {
  res.status(404).json({ error: 'Not found' });
}

// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, next) {
  // Prisma unique-constraint violation.
  if (err?.code === 'P2002') {
    return res.status(409).json({ error: 'Resource already exists' });
  }
  // Never leak stack/details to client. Log server-side without sensitive bodies.
  console.error('Unhandled error:', err?.message || err);
  res.status(500).json({ error: 'Internal server error' });
}
