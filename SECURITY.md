# Security Policy

## Reporting a vulnerability

If you find a security issue in Yomira, please report it **privately** — do not
open a public issue.

- Email: **thibaultpernel@gmail.com** (subject: `Yomira security`)
- Or use GitHub's *Report a vulnerability* (Security tab → Advisories).

Please include steps to reproduce and the affected version. You'll get a
response as soon as possible, and credit if you'd like once it's fixed.

## Scope

The app is a Flutter client. It stores a session JWT in the platform secure
store (Android Keystore), sends only an `INTERNET`-level connection to the
configured backend/content servers, and ships no ads, analytics, or trackers.

## Good to know

- The real runtime config (`.env`) is **never** committed — it's gitignored.
  Builds read it from a local copy of `.env.example`.
- Reading-progress sync is optional and tied to your own account.
