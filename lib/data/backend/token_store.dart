import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/config.dart';

/// Persists the JWT in platform secure storage (Android Keystore — no GMS).
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  Future<String?> read() => _storage.read(key: AppConfig.jwtStorageKey);

  Future<void> write(String token) =>
      _storage.write(key: AppConfig.jwtStorageKey, value: token);

  Future<void> clear() => _storage.delete(key: AppConfig.jwtStorageKey);
}
