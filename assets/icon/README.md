# App icons

Put **one** file here:

| File | Format | Size |
|------|--------|------|
| `app_icon.png` | **PNG** (not JPEG) | square, ideally **1024×1024** (min 512) |

Rename your image to exactly `app_icon.png`. If it's a `.jpg`/`.jpeg`, convert
it to PNG first.

## Generate all platform icons

```bash
cd flutter
flutter pub get
dart run flutter_launcher_icons
```

Writes Android (`mipmap-*`), iOS (`AppIcon.appiconset`), and Windows
(`windows/runner/resources/app_icon.ico`). Then rebuild: `flutter run` / `flutter build ...`.

## Optional: sharper Android adaptive icon
Android crops the icon to a circle/squircle and the corners get cut. For a clean
result, also add `app_icon_foreground.png` — a **transparent** PNG with the
symbol centered and ~25% empty padding on each side — and point
`adaptive_icon_foreground` at it in `pubspec.yaml`.
