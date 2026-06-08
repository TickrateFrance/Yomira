// Single PrismaClient instance reused across the process.
import { PrismaClient } from '@prisma/client';

const base = new PrismaClient({
  // Do not log query params (may contain usernames). Errors/warns only.
  log: ['warn', 'error'],
});

// Defense-in-depth: a user-scoped query with userId === undefined would make
// Prisma drop the filter and read/delete every user's rows. Refuse it.
export const prisma = base.$extends({
  query: {
    $allModels: {
      async $allOperations({ args, query }) {
        const where = args?.where;
        if (where && 'userId' in where && where.userId === undefined) {
          throw new Error('Refusing query with undefined userId');
        }
        return query(args);
      },
    },
  },
});

export async function disconnectPrisma() {
  await base.$disconnect();
}
