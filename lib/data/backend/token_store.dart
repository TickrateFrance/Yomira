import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/config.dart';

/// Persists the JWT in platform secure storage (Android Keystore — no GMS).
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// In-memory copy so callers (e.g. image headers) can read it synchronously.
  String? _cached;
  String? get cachedToken => _cached;

  Future<String?> read() async {
    _cached = await _storage.read(key: AppConfig.jwtStorageKey);
    return _cached;
  }

  Future<void> write(String token) async {
    _cached = token;
    await _storage.write(key: AppConfig.jwtStorageKey, value: token);
  }

  Future<void> clear() async {
    _cached = null;
    await _storage.delete(key: AppConfig.jwtStorageKey);
  }
}
