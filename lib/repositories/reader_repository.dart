import 'package:dio/dio.dart';
import 'package:isar/isar.dart';

import '../data/backend/backend_api.dart';
import '../data/backend/models/sync_models.dart';
import '../data/local/isar_db.dart';
import '../data/local/models/local_models.dart';
import '../data/sources/source_registry.dart';

/// Resolves page image URLs for the reader and records progress.
///
/// Page resolution is delegated to the content source (via [SourceRegistry]).
/// MangaDex baseUrls expire (~15 min) — that source caches them in memory and
/// refreshes on expiry/403; ComicK URLs are stable. All ids are **globalIds**
/// ("mangadex:uuid" / "comick:hid").
class ReaderRepository {
  ReaderRepository(this._sources, this._backend, this._db);

  final SourceRegistry _sources;
  final BackendApi _backend;
  final LocalDb _db;

  Future<int> pageCount(String chapterGlobalId, bool dataSaver) async {
    final (source, rawId) = SourceRegistry.parseGlobalId(chapterGlobalId);
    return _sources.of(source).pageCount(rawId, dataSaver: dataSaver);
  }

  Future<String> pageUrl(String chapterGlobalId, int index, bool dataSaver) async {
    final (source, rawId) = SourceRegistry.parseGlobalId(chapterGlobalId);
    return _sources.of(source).pageUrl(rawId, index, dataSaver: dataSaver);
  }

  /// Forced refresh of page URL — call after a 403/expired CDN response.
  Future<String> refreshedPageUrl(String chapterGlobalId, int index, bool dataSaver) async {
    final (source, rawId) = SourceRegistry.parseGlobalId(chapterGlobalId);
    return _sources.of(source).pageUrl(rawId, index, dataSaver: dataSaver, refresh: true);
  }

  /// Record progress locally (offline-first) and try to push to backend.
  Future<void> saveProgress({
    required String mangaId,
    required String chapterId,
    required int lastPage,
    required bool read,
    String? chapterNumber,
    String? language,
  }) async {
    final local = LocalProgress()
      ..mangaId = mangaId
      ..chapterId = chapterId
      ..chapterNumber = chapterNumber
      ..language = language
      ..lastPage = lastPage
      ..read = read
      ..dirty = true
      ..updatedAt = DateTime.now();

    final history = LocalHistory()
      ..mangaId = mangaId
      ..lastReadAt = DateTime.now();

    await _db.isar.writeTxn(() async {
      await _db.isar.progress.put(local);
      await _db.isar.history.put(history);
    });

    // Attach a title/cover snapshot (from local cache) so the backend can
    // persist it on history — that's what survives a reinstall.
    final cachedManga =
        await _db.isar.cachedManga.where().mangaIdEqualTo(mangaId).findFirst();

    // Best-effort backend sync; stays dirty if it fails.
    try {
      await _backend.putProgress(ProgressEntry(
        mangaId: mangaId,
        chapterId: chapterId,
        lastPage: lastPage,
        read: read,
        chapterNumber: chapterNumber,
        language: language,
        title: cachedManga?.title,
        coverUrl: cachedManga?.coverUrl,
      ));
      await _db.isar.writeTxn(() async {
        final saved = await _db.isar.progress
            .where()
            .chapterIdEqualTo(chapterId)
            .findFirst();
        if (saved != null) {
          saved.dirty = false;
          await _db.isar.progress.put(saved);
        }
      });
    } on DioException {
      // Offline / server down — leave dirty for later push.
    }
  }

  /// Resume point for a chapter (local).
  Future<LocalProgress?> progressFor(String chapterId) {
    return _db.isar.progress.where().chapterIdEqualTo(chapterId).findFirst();
  }

  /// Mark one or more chapters read/unread from the chapter list WITHOUT
  /// touching history (you're not actually opening them). Writes locally first
  /// (instant), then best-effort syncs each to the backend.
  Future<void> setChaptersRead({
    required String mangaId,
    required List<({String chapterId, String? number, String language})> chapters,
    required bool read,
  }) async {
    final now = DateTime.now();
    await _db.isar.writeTxn(() async {
      for (final c in chapters) {
        final existing = await _db.isar.progress
            .where()
            .chapterIdEqualTo(c.chapterId)
            .findFirst();
        final row = (existing ?? LocalProgress())
          ..mangaId = mangaId
          ..chapterId = c.chapterId
          ..chapterNumber = c.number ?? existing?.chapterNumber
          ..language = c.language.isNotEmpty ? c.language : existing?.language
          ..lastPage = read ? (existing?.lastPage ?? 0) : 0
          ..read = read
          ..dirty = true
          ..updatedAt = now;
        await _db.isar.progress.put(row);
      }
    });

    final cached =
        await _db.isar.cachedManga.where().mangaIdEqualTo(mangaId).findFirst();
    for (final c in chapters) {
      try {
        await _backend.putProgress(ProgressEntry(
          mangaId: mangaId,
          chapterId: c.chapterId,
          lastPage: 0,
          read: read,
          chapterNumber: c.number,
          language: c.language,
          title: cached?.title,
          coverUrl: cached?.coverUrl,
        ));
        await _db.isar.writeTxn(() async {
          final s = await _db.isar.progress
              .where()
              .chapterIdEqualTo(c.chapterId)
              .findFirst();
          if (s != null) {
            s.dirty = false;
            await _db.isar.progress.put(s);
          }
        });
      } on DioException {
        break; // offline — remaining rows stay dirty for a later push
      }
    }
  }
}
