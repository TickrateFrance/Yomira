import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/background_settings.dart';

/// Persists [BackgroundSettings] on-device.
class BackgroundStore {
  BackgroundStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _key = 'background_settings';
  final FlutterSecureStorage _storage;

  Future<BackgroundSettings> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return const BackgroundSettings();
      return BackgroundSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const BackgroundSettings();
    }
  }

  Future<void> save(BackgroundSettings settings) async {
    await _storage.write(key: _key, value: jsonEncode(settings.toJson()));
  }
}
