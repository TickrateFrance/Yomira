// Body/params/query validation via zod schemas.
// Usage: router.post('/', validate({ body: schema }), handler)
export function validate(schemas) {
  return (req, res, next) => {
    try {
      if (schemas.body) req.body = schemas.body.parse(req.body);
      if (schemas.params) req.params = schemas.params.parse(req.params);
      if (schemas.query) req.query = schemas.query.parse(req.query);
      return next();
    } catch (err) {
      if (err?.issues) {
        return res.status(400).json({
          error: 'Validation failed',
          details: err.issues.map((i) => ({
            path: i.path.join('.'),
            message: i.message,
          })),
        });
      }
      return next(err);
    }
  };
}
