import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';

/// Runtime configuration that can change without rebuilding the app.
class RuntimeConfig {
  const RuntimeConfig({
    required this.backendBaseUrl,
    this.suwayomiUser = '',
    this.suwayomiPass = '',
  });

  final String backendBaseUrl;

  /// Credentials for Suwayomi HTTP Basic Auth (blank = no auth sent).
  final String suwayomiUser;
  final String suwayomiPass;

  /// `Basic <base64>` header value, or null when no credentials are set.
  String? get suwayomiAuthHeader {
    if (suwayomiUser.isEmpty && suwayomiPass.isEmpty) return null;
    final token = base64Encode(utf8.encode('$suwayomiUser:$suwayomiPass'));
    return 'Basic $token';
  }

  RuntimeConfig copyWith({
    String? backendBaseUrl,
    String? suwayomiUser,
    String? suwayomiPass,
  }) =>
      RuntimeConfig(
        backendBaseUrl: backendBaseUrl ?? this.backendBaseUrl,
        suwayomiUser: suwayomiUser ?? this.suwayomiUser,
        suwayomiPass: suwayomiPass ?? this.suwayomiPass,
      );
}

/// Persists in-app overrides (backend URL + Suwayomi login) and resolves the
/// effective values. Priority: in-app override > `.env` > compile-time default.
class ConfigStore {
  ConfigStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage();

  static const _overrideKey = 'backend_base_url_override';
  static const _suwUserKey = 'suwayomi_user_override';
  static const _suwPassKey = 'suwayomi_pass_override';

  final FlutterSecureStorage _storage;

  /// Loads the .env asset. Safe to call once at startup; missing file is OK.
  static Future<void> loadEnv() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // No .env bundled / parse error — fall through to defaults.
    }
  }

  String _normalize(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// The .env value, if present and non-empty.
  String? get envUrl {
    final v = dotenv.maybeGet('BACKEND_BASE_URL');
    return (v != null && v.trim().isNotEmpty) ? _normalize(v) : null;
  }

  /// Suwayomi-Server base URL (.env SUWAYOMI_BASE). Empty = source disabled.
  String get suwayomiBase {
    final v = dotenv.maybeGet('SUWAYOMI_BASE');
    return (v != null && v.trim().isNotEmpty) ? _normalize(v) : '';
  }

  String get _envSuwUser => (dotenv.maybeGet('SUWAYOMI_USER') ?? '').trim();
  String get _envSuwPass => dotenv.maybeGet('SUWAYOMI_PASS') ?? '';

  /// Discord Rich Presence application id (.env DISCORD_APP_ID). Empty = off.
  String get discordAppId => (dotenv.maybeGet('DISCORD_APP_ID') ?? '').trim();

  /// Resolve the effective backend URL at startup (override > .env > default).
  Future<String> resolveInitial() async {
    final override = await _storage.read(key: _overrideKey);
    if (override != null && override.trim().isNotEmpty) return _normalize(override);
    return envUrl ?? AppConfig.defaultBackendBase;
  }

  /// Resolve Suwayomi credentials at startup (override > .env).
  Future<(String, String)> resolveSuwayomiCreds() async {
    final u = await _storage.read(key: _suwUserKey);
    final p = await _storage.read(key: _suwPassKey);
    return (
      (u != null && u.isNotEmpty) ? u : _envSuwUser,
      (p != null && p.isNotEmpty) ? p : _envSuwPass,
    );
  }

  Future<void> saveOverride(String url) =>
      _storage.write(key: _overrideKey, value: _normalize(url));

  Future<void> clearOverride() => _storage.delete(key: _overrideKey);

  Future<void> saveSuwayomiCreds(String user, String pass) async {
    await _storage.write(key: _suwUserKey, value: user);
    await _storage.write(key: _suwPassKey, value: pass);
  }
}

/// Holds the live runtime config. Updating it rebuilds the dependent Dio
/// clients / image headers via Riverpod.
class ConfigController extends StateNotifier<RuntimeConfig> {
  ConfigController(this._store, RuntimeConfig initial) : super(initial);

  final ConfigStore _store;

  Future<void> setBackendUrl(String url) async {
    await _store.saveOverride(url);
    state = state.copyWith(backendBaseUrl: _store._normalize(url));
  }

  Future<void> resetBackendUrl() async {
    await _store.clearOverride();
    state = state.copyWith(
      backendBaseUrl: _store.envUrl ?? AppConfig.defaultBackendBase,
    );
  }

  /// Set the Suwayomi login (persisted). Applies on the next request.
  Future<void> setSuwayomiCreds(String user, String pass) async {
    await _store.saveSuwayomiCreds(user, pass);
    state = state.copyWith(suwayomiUser: user, suwayomiPass: pass);
  }
}
