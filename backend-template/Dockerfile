# Yomira backend template image.
FROM node:20-alpine AS base
WORKDIR /app

# OpenSSL is needed by the Prisma engines on alpine.
RUN apk add --no-cache openssl

# Install deps (dev deps included so "prisma generate" can run).
COPY package.json ./
RUN npm install

# Prisma client generation needs the schema.
COPY prisma ./prisma
RUN npx prisma generate

COPY src ./src

ENV NODE_ENV=production
EXPOSE 3000

# Apply pending migrations, then start. (migrate deploy is a no-op when up to date.)
CMD ["sh", "-c", "npx prisma migrate deploy && node src/index.js"]
