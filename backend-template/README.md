# Yomira backend template

A blank, self-hostable **sync backend** for the [Yomira](../flutter) manga reader
app. It stores **accounts and reading-progress metadata only** - no manga, no
sources, no page images. This is a clean reference you copy and run as your own;
fill in your secrets and point the app at it.

> This template is intentionally minimal. It implements exactly the HTTP contract
> the app needs. The content server (Suwayomi) is a separate service you run on
> your own - see the app README for that.

## What it provides

- Username/password accounts with bcrypt hashing and JWT sessions
- Bidirectional reading-progress, library (favorites) and history sync
- App version gating (soft/force update) via the `app_versions` table
- Postgres storage through Prisma
- One-command Docker stack (Postgres + API)

## Quick start (Docker)

```bash
cp .env.example .env
# Edit .env: set a strong JWT_SECRET (the app refuses to boot on the example value)
# and change the Postgres credentials.

docker compose up --build
```

The API is published on `http://localhost:3000`. Migrations are applied
automatically on container start (`prisma migrate deploy`).

Health check:

```bash
curl http://localhost:3000/health     # {"status":"ok"}
```

## Quick start (local Node, no Docker)

```bash
npm install
cp .env.example .env                   # edit it; point DATABASE_URL at your Postgres
npm run prisma:deploy                  # apply migrations
npm run dev                            # watch mode on PORT (default 3000)
```

## Configuration

All config is environment-driven and validated at startup (`src/config/env.js`).
Bad config fails fast with a readable error.

| Variable | Default | Purpose |
|---|---|---|
| `DATABASE_URL` | - | Postgres connection string (Prisma). With compose the host is `db`. |
| `JWT_SECRET` | - | JWT signing secret, min 16 chars. Must NOT be the example value. |
| `JWT_EXPIRES_IN` | `7d` | Token lifetime (zeit/ms style: `7d`, `12h`, `30m`). |
| `BCRYPT_ROUNDS` | `12` | bcrypt cost factor (10-15). |
| `PORT` | `3000` | API listen port. |
| `CORS_ORIGINS` | `*` | Comma-separated allowed origins, or `*` for any (dev only). |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | `yomira` | Credentials for the compose `db` container. |

Generate a secret:

```bash
node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
```

## API

All responses are JSON. Authenticated routes need `Authorization: Bearer <token>`.

### Auth

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/auth/register` | `{username, password}` | `201 {token, user}` |
| POST | `/auth/login` | `{username, password}` | `200 {token, user}` |
| GET | `/auth/me` | - | `200 {user}` |
| ALL | `/auth/verify` | - | `200 {ok:true}` if JWT valid, else `401` |

`username`: 3-32 chars, `[a-zA-Z0-9_.-]`. `password`: 8-128 chars.

`/auth/verify` does no DB hit and is suitable as a reverse-proxy `forward_auth`
target to gate another service (e.g. Suwayomi) behind app login.

### Reading progress

| Method | Path | Notes |
|---|---|---|
| GET | `/progress` | all progress rows for the user |
| GET | `/progress/:mangaId` | progress rows for one manga |
| PUT | `/progress` | upsert one chapter; also bumps history |

`PUT /progress` body:

```json
{
  "mangaId": "string",
  "chapterId": "string",
  "lastPage": 0,
  "read": false,
  "chapterNumber": "10.5",
  "language": "en",
  "title": "optional snapshot",
  "coverUrl": "optional snapshot"
}
```

`title`/`coverUrl` are optional snapshots stored on the history row so history
renders without a live fetch.

### Library (favorites)

| Method | Path | Body | Notes |
|---|---|---|---|
| GET | `/library` | - | favorites, newest first |
| POST | `/library` | `{mangaId}` | idempotent add |
| DELETE | `/library/:mangaId` | - | `204` |

### History

| Method | Path | Notes |
|---|---|---|
| GET | `/history?limit=50` | newest first, limit 1-200 |
| DELETE | `/history/:mangaId` | `204` |

### App status / update gating

| Method | Path | Notes |
|---|---|---|
| GET | `/api/v1/app-status` | reads `X-App-Version` + `X-Platform` headers |

Returns `{status, url}` where `status` is `none` | `soft` | `force`. Public and
ungated so a force-updated client can still read the download URL. Every other
route below `/api/v1/app-status` is gated: a client older than the platform
minimum gets `426 Upgrade Required`.

Populate the `app_versions` table per platform to drive this:

| Column | Example |
|---|---|
| `platform` | `android` / `windows` |
| `latest_version` | `1.4.0` |
| `min_required_version` | `1.2.0` |
| `url` | download/landing page URL |

Leave the table empty to disable update gating entirely.

## Data model

Postgres via Prisma (`prisma/schema.prisma`). `DateTime` columns are
`TIMESTAMP(3)` and serialize as ISO-8601. No images are ever stored.

- `users` - id, username, password_hash, created_at, updated_at
- `reading_progress` - id, user_id, manga_id, chapter_id, last_page, read, chapter_number, language, updated_at  (unique on user+chapter)
- `library` - id, user_id, manga_id, added_at  (unique on user+manga)
- `history` - id, user_id, manga_id, title, cover_url, last_read_at  (unique on user+manga)
- `app_versions` - id, platform, latest_version, min_required_version, url, updated_at  (unique on platform)

Deleting a user cascades to their progress, library and history rows.

## Production notes

- **Always put this behind TLS.** The Android release build refuses cleartext
  HTTP. Terminate TLS with a reverse proxy (Caddy, nginx, Traefik) and forward
  to the API container. Remove the public `ports:` mapping on `api` once a proxy
  fronts it.
- Keep Postgres bound to localhost / the compose network only - never expose it.
- Use a long random `JWT_SECRET` and rotate it if leaked (invalidates all tokens).
- Set `CORS_ORIGINS` to your real origins in production instead of `*`.

## Project layout

```
backend-template/
  Dockerfile
  docker-compose.yml
  .env.example
  package.json
  prisma/
    schema.prisma
    migrations/            # initial migration (creates all tables)
  src/
    index.js              # Express app + middleware wiring
    config/env.js         # zod-validated environment
    lib/prisma.js         # PrismaClient singleton (+ userId guard)
    middleware/           # auth, validate, error, version-gate
    routes/               # auth, progress, library, history, app-status
    utils/                # jwt, version compare
```
