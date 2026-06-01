# Privacy

Yomira is designed to collect as little as possible.

## What it does NOT do
- No Google Mobile Services, no Firebase, no FCM.
- No ads, no analytics, no trackers, no telemetry, no crash reporting to third parties.
- No selling or sharing of any data.

## What it does
- **Content**: fetched from the content sources you configure (a Suwayomi
  server running community extensions). Yomira hosts nothing itself.
- **Account (optional)**: if you sign in, the backend stores your username, a
  hashed password, and your reading progress / library / history — solely to
  sync those across your own devices. You can read without an account.
- **On-device**: cached covers/metadata and reading progress are stored locally
  (Isar) for offline use. The session token is kept in the OS secure store.

## Permissions
- **Android**: `INTERNET` only.

## Your data
Deleting your account removes its synced data. Uninstalling the app removes all
local data.

Questions: thibaultpernel@gmail.com
