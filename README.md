<div align="center">

<img src="docs/icon.png" width="96" height="96" alt="Yomira" />

# Yomira

**A clean, ad-free manga, manhwa & manhua reader for Android and Windows.**

Read across hundreds of community sources in English and French, with
cross-device reading-progress sync. No ads. No tracking. No Google services.

<!-- Replace OWNER/REPO with your GitHub path -->
[![Build APK](https://github.com/OWNER/REPO/actions/workflows/build.yml/badge.svg)](https://github.com/OWNER/REPO/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-FF8FB1.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows-C4A7E7.svg)](#download)

</div>

---

## Screenshots

| Library | Search | Reader |
|:---:|:---:|:---:|
| <img src="docs/library.png" width="220" /> | <img src="docs/search.png" width="220" /> | <img src="docs/reader.png" width="220" /> |

## Download

Get the latest build from **[yomira.eu](https://yomira.eu)** or the
[**Releases**](https://github.com/OWNER/REPO/releases) page:

- **Android** — `Yomira-latest.apk` (Android 8.0+). Sideload it; you'll be asked
  to allow "install from this source" — expected for an app outside the Play Store.
- **Windows** — `Yomira-Setup.exe` (Windows 10/11, x64).

### Verify your download

Every release ships a `SHA256SUMS.txt`. Confirm the file wasn't tampered with:

```powershell
# Windows
Get-FileHash .\Yomira-latest.apk -Algorithm SHA256
```
```bash
# Linux / macOS
sha256sum Yomira-latest.apk
```
The hash must match the one in `SHA256SUMS.txt`.

## Privacy

Yomira is built to be boring on purpose — it does **not** phone home.

- **No** Google Mobile Services, **no** Firebase, **no** FCM.
- **No** ads, **no** analytics, **no** trackers, **no** telemetry.
- The only Android permission requested is **INTERNET** (to fetch content).
- An account is optional and only used to **sync your reading progress** between
  your own devices — nothing else is collected.
- The optional NSFW source filter is **off by default**.

See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).

## Features

- Search hundreds of manga / manhwa / manhua sources from one place
- Reading-progress sync across phone + desktop
- Distraction-free reader: vertical (webtoon) & horizontal (manga) modes,
  adjustable page width, hideable bars, image prefetch
- Smart history with "continue where you left off"
- Library / favorites
- Adaptive UI — native on Android, desktop layout on Windows
- Built-in update checker

## Build from source

Want to verify the app or build it yourself? You only need the Flutter SDK.

```bash
# 1. Clone
git clone https://github.com/OWNER/REPO.git
cd REPO

# 2. Configure (the real .env is never committed)
cp .env.example .env
#   edit .env — point BACKEND_BASE_URL / SUWAYOMI_BASE at your own server

# 3. Generate native scaffolding + Isar code (not checked in)
flutter create . --platforms=android,windows --org fr.tickrate
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# 4. Build
flutter build apk --release          # Android
flutter build windows --release      # Windows
```

> Yomira needs a backend (accounts/sync) and a Suwayomi server (content). Point
> `.env` at your own instances — the public Yomira server is private to its users.

## Tech

Flutter · Riverpod · go_router · dio · Isar (local DB) · cached_network_image ·
flutter_secure_storage (JWT in the Android Keystore — no GMS). Content comes
from a self-hosted [Suwayomi](https://github.com/Suwayomi/Suwayomi-Server)
server running community extensions.

## Disclaimer

Yomira **hosts no content**. It is a reader that displays material from
third-party community sources you configure yourself. It bundles no sources and
ships no copyrighted material. Please support official releases where available.

## Credits & license

Made by **[Tickrate](https://tickrate.fr)** · Pralexio.
Released under the [MIT License](LICENSE).
