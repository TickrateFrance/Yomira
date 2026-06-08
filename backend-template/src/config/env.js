// Load + validate environment. Fail fast on bad config.
import { z } from 'zod';

const schema = z.object({
  DATABASE_URL: z.string().min(1, 'DATABASE_URL required'),
  JWT_SECRET: z
    .string()
    .min(16, 'JWT_SECRET must be at least 16 chars')
    .refine((v) => v !== 'change-me-to-a-long-random-secret', {
      message: 'JWT_SECRET still set to the example value',
    }),
  JWT_EXPIRES_IN: z.string().default('7d'),
  BCRYPT_ROUNDS: z.coerce.number().int().min(10).max(15).default(12),
  PORT: z.coerce.number().int().positive().default(3000),
  CORS_ORIGINS: z.string().default('*'),
});

const parsed = schema.safeParse(process.env);

if (!parsed.success) {
  // Print readable errors then exit. Never print secret values.
  console.error('Invalid environment configuration:');
  for (const issue of parsed.error.issues) {
    console.error(`  - ${issue.path.join('.')}: ${issue.message}`);
  }
  process.exit(1);
}

const raw = parsed.data;

export const env = {
  ...raw,
  corsOrigins:
    raw.CORS_ORIGINS === '*'
      ? '*'
      : raw.CORS_ORIGINS.split(',')
          .map((s) => s.trim())
          .filter(Boolean),
};
