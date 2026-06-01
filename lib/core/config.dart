import 'dart:io';

/// App-wide constants and runtime config.
class AppConfig {
  /// Client version sent as X-App-Version. Keep in sync with pubspec version.
  static const String appVersion = '1.2.7';

  /// Platform tag sent as X-Platform (matches AppVersion.platform on backend).
  static String get platform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

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
