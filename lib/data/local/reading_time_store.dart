import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persists per-day reading time as a tiny JSON file in the app documents dir:
/// {"2026-06-10": 1234, ...} (seconds spent with the reader open that day).
/// File-based on purpose: no schema, no codegen, works on phone and desktop.
class ReadingTimeStore {
  static const _fileName = 'reading_time.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  String _key(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  /// All recorded days: yyyy-MM-dd -> seconds.
  Future<Map<String, int>> all() async {
    try {
      final f = await _file();
      if (!await f.exists()) return {};
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return raw.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  /// Add [seconds] to [day]'s total. Ignores non-positive values.
  Future<void> add(DateTime day, int seconds) async {
    if (seconds <= 0) return;
    try {
      final map = await all();
      final k = _key(day);
      map[k] = (map[k] ?? 0) + seconds;
      final f = await _file();
      await f.writeAsString(jsonEncode(map));
    } catch (_) {
      // Time tracking is best-effort; never break reading over it.
    }
  }
}
