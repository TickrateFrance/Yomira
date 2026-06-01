import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/reader_settings.dart';

/// Persists [ReaderSettings] on-device (mode, quality, page width).
class ReaderPrefsStore {
  ReaderPrefsStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _key = 'reader_settings';
  final FlutterSecureStorage _storage;

  Future<ReaderSettings> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return const ReaderSettings();
      return ReaderSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ReaderSettings();
    }
  }

  Future<void> save(ReaderSettings settings) async {
    await _storage.write(key: _key, value: jsonEncode(settings.toJson()));
  }
}
