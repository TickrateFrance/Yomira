import 'dart:convert';
import 'dart:io';

/// App-wide constants and runtime config.
class AppConfig {
  /// Client version sent as X-App-Version. Keep in sync with pubspec version.
  static const String appVersion = '1.3.2';

  /// Platform tag sent as X-Platform (matches AppVersion.platform on backend).
  static String get platform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  /// Direct binary download location for in-app self-update.
  static const String updateBaseUrl = 'https://yomira.eu/downloads';

  /// The platform-specific installer URL the in-app updater downloads. Null on
  /// platforms where self-update isn't supported (the UI falls back to a link).
  static String? get directUpdateUrl {
    if (Platform.isAndroid) return '$updateBaseUrl/Yomira-latest.apk';
    if (Platform.isWindows) return '$updateBaseUrl/Yomira-Setup.exe';
    return null;
  }

  /// Basic-Auth login for the gated /downloads/ folder, so the in-app updater
  /// can fetch the installer without showing a password prompt. NOTE: these are
  /// embedded in the binary and can be extracted by decompiling — fine for a
  /// private, friends-only app, but don't reuse this password elsewhere.
  static const String _updateUser = 'yomira';
  static const String _updatePass = 'Private33Yomira33Download';

  /// `Authorization` header value for download requests. Empty if no creds set.
  static String get updateAuthHeader => _updateUser.isEmpty
      ? ''
      : 'Basic ${base64Encode(utf8.encode('$_updateUser:$_updatePass'))}';

  /// MangaDex public API base. Read endpoints need no auth.
  static const String mangadexApiBase = 'https://api.mangadex.org';

  /// MangaDex cover image host. Covers built as:
  /// `https://uploads.mangadex.org/covers/<mangaId>/<coverFileName>`
  static const String mangadexUploadsBase = 'https://uploads.mangadex.org';

  /// Last-resort fallback backend URL, used only if there's no in-app override
  /// and no value in the bundled .env. Resolved at runtime by [ConfigStore] —
  /// see lib/core/runtime_config.dart. Priority: in-app setting > .env > this.
  /// A --dart-define can still seed this default, but is no longer required.
  static const String defaultBackendBase = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  /// Identifies the app to MangaDex per their guidelines.
  static const String userAgent = 'TAppReader/1.0 (private; +github.com/tappreader)';

  /// Rate limits (MangaDex guidelines).
  static const int globalRequestsPerSecond = 5;
  static const int atHomeRequestsPerMinute = 40;

  /// at-home baseUrl lifetime is ~15 min; refresh well before that.
  static const Duration atHomeUrlTtl = Duration(minutes: 10);

  /// Secure-storage key for the JWT.
  static const String jwtStorageKey = 'tappreader_jwt';
}

/// Image quality for the reader.
enum ReaderQuality { data, dataSaver }

extension ReaderQualityPath on ReaderQuality {
  /// Path segment used in MangaDex at-home image URLs.
  String get pathSegment => this == ReaderQuality.data ? 'data' : 'data-saver';
}
