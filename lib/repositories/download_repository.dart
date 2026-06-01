import 'dart:io';

import 'package:dio/dio.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/local/isar_db.dart';
import '../data/local/models/local_models.dart';
import '../data/sources/source_registry.dart';

/// Downloads chapter images to app storage for offline reading.
/// Ids are globalIds; page resolution goes through the source registry.
class DownloadRepository {
  DownloadRepository(this._sources, this._db, this._dio);

  final SourceRegistry _sources;
  final LocalDb _db;
  final Dio _dio; // plain dio for image bytes

  Future<bool> isDownloaded(String chapterId) async {
    final row =
        await _db.isar.downloads.where().chapterIdEqualTo(chapterId).findFirst();
    return row != null && row.pagePaths.isNotEmpty;
  }

  Future<DownloadedChapter?> get(String chapterId) {
    return _db.isar.downloads.where().chapterIdEqualTo(chapterId).findFirst();
  }

  Future<List<DownloadedChapter>> all() => _db.isar.downloads.where().findAll();

  /// Download all pages of [chapterId]. [onProgress] gives (done, total).
  Future<DownloadedChapter> download({
    required String mangaId,
    required String chapterId,
    bool dataSaver = false,
    void Function(int done, int total)? onProgress,
  }) async {
    final (source, rawId) = SourceRegistry.parseGlobalId(chapterId);
    final src = _sources.of(source);
    final total = await src.pageCount(rawId, dataSaver: dataSaver);

    final dir = await _chapterDir(chapterId);
    final paths = <String>[];

    for (var i = 0; i < total; i++) {
      var url = await src.pageUrl(rawId, i, dataSaver: dataSaver);
      final dest = p.join(dir.path, _pageFileName(i, url));
      try {
        await _dio.download(url, dest);
      } on DioException catch (e) {
        // URL may have expired mid-download (MangaDex) → refresh once, retry.
        if (e.response?.statusCode == 403) {
          url = await src.pageUrl(rawId, i, dataSaver: dataSaver, refresh: true);
          await _dio.download(url, dest);
        } else {
          rethrow;
        }
      }
      paths.add(dest);
      onProgress?.call(i + 1, total);
    }

    final entry = DownloadedChapter()
      ..chapterId = chapterId
      ..mangaId = mangaId
      ..pagePaths = paths
      ..pageCount = paths.length
      ..downloadedAt = DateTime.now();
    await _db.isar.writeTxn(() => _db.isar.downloads.put(entry));
    return entry;
  }

  Future<void> delete(String chapterId) async {
    final row = await get(chapterId);
    if (row != null) {
      final dir = await _chapterDir(chapterId);
      if (await dir.exists()) await dir.delete(recursive: true);
      await _db.isar.writeTxn(() async {
        await _db.isar.downloads.delete(fastHash(chapterId));
      });
    }
  }

  Future<Directory> _chapterDir(String chapterId) async {
    final base = await getApplicationDocumentsDirectory();
    // Sanitize the globalId (contains ':') for use as a folder name.
    final safe = chapterId.replaceAll(':', '_');
    final dir = Directory(p.join(base.path, 'chapters', safe));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _pageFileName(int index, String url) {
    final ext = p.extension(Uri.parse(url).path);
    final padded = index.toString().padLeft(4, '0');
    return '$padded${ext.isEmpty ? '.jpg' : ext}';
  }
}
