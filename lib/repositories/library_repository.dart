import 'package:dio/dio.dart';
import 'package:isar/isar.dart';

import '../data/backend/backend_api.dart';
import '../data/local/isar_db.dart';
import '../data/local/models/local_models.dart';

/// Library (favorites) + history, offline-first with backend sync.
class LibraryRepository {
  LibraryRepository(this._backend, this._db);

  final BackendApi _backend;
  final LocalDb _db;

  // ---- Library ----

  Future<List<LocalLibrary>> localLibrary() {
    return _db.isar.library.where().findAll();
  }

  Future<bool> isFavorite(String mangaId) async {
    final row =
        await _db.isar.library.where().mangaIdEqualTo(mangaId).findFirst();
    return row != null && row.present;
  }

  Future<void> addFavorite(String mangaId) async {
    final row = LocalLibrary()
      ..mangaId = mangaId
      ..present = true
      ..dirty = true
      ..addedAt = DateTime.now();
    await _db.isar.writeTxn(() => _db.isar.library.put(row));
    try {
      await _backend.addLibrary(mangaId);
      await _clearDirty(mangaId);
    } on DioException {
      // stays dirty
    }
  }

  Future<void> removeFavorite(String mangaId) async {
    final existing =
        await _db.isar.library.where().mangaIdEqualTo(mangaId).findFirst();
    final row = (existing ?? (LocalLibrary()..mangaId = mangaId))
      ..present = false
      ..dirty = true;
    await _db.isar.writeTxn(() => _db.isar.library.put(row));
    try {
      await _backend.removeLibrary(mangaId);
      // Fully drop the row once removal is confirmed.
      await _db.isar.writeTxn(() async {
        await _db.isar.library.delete(fastHash(mangaId));
      });
    } on DioException {
      // stays dirty (present=false) for later push
    }
  }

  Future<void> _clearDirty(String mangaId) async {
    await _db.isar.writeTxn(() async {
      final r = await _db.isar.library.where().mangaIdEqualTo(mangaId).findFirst();
      if (r != null) {
        r.dirty = false;
        await _db.isar.library.put(r);
      }
    });
  }

  // ---- History ----

  Future<List<LocalHistory>> localHistory({int limit = 50}) {
    return _db.isar.history
        .where()
        .sortByLastReadAtDesc()
        .limit(limit)
        .findAll();
  }

  /// Remove a manga from history locally and on the backend (so it doesn't
  /// reappear on the next sync). Best-effort backend; local is authoritative.
  Future<void> deleteHistory(String mangaId) async {
    await _db.isar.writeTxn(() => _db.isar.history.delete(fastHash(mangaId)));
    try {
      await _backend.deleteHistory(mangaId);
    } on DioException {
      // Offline — local removal stands; backend reconciles next time.
    }
  }

  /// Pull backend state into local cache (call after login / on refresh).
  /// Also restores reading progress and a title/cover snapshot, so history and
  /// resume-points survive a reinstall or a fresh device.
  Future<void> pullFromBackend() async {
    try {
      final lib = await _backend.getLibrary();
      final hist = await _backend.getHistory(limit: 100);
      final prog = await _backend.getProgress();
      await _db.isar.writeTxn(() async {
        for (final e in lib) {
          await _db.isar.library.put(LocalLibrary()
            ..mangaId = e.mangaId
            ..present = true
            ..dirty = false
            ..addedAt = e.addedAt ?? DateTime.now());
        }
        for (final h in hist) {
          await _db.isar.history.put(LocalHistory()
            ..mangaId = h.mangaId
            ..lastReadAt = h.lastReadAt ?? DateTime.now());
          // Seed the metadata cache from the snapshot when we don't already
          // have a (richer) local entry — gives history its title + cover.
          if ((h.title ?? '').isNotEmpty) {
            final existing = await _db.isar.cachedManga
                .where()
                .mangaIdEqualTo(h.mangaId)
                .findFirst();
            if (existing == null) {
              await _db.isar.cachedManga.put(CachedManga()
                ..mangaId = h.mangaId
                ..title = h.title!
                ..coverUrl = h.coverUrl
                ..updatedAt = DateTime.now());
            }
          }
        }
        for (final p in prog) {
          // Don't clobber a local row that hasn't been pushed yet.
          final existing = await _db.isar.progress
              .where()
              .chapterIdEqualTo(p.chapterId)
              .findFirst();
          if (existing != null && existing.dirty) continue;
          await _db.isar.progress.put(LocalProgress()
            ..mangaId = p.mangaId
            ..chapterId = p.chapterId
            ..chapterNumber = p.chapterNumber
            ..language = p.language
            ..lastPage = p.lastPage
            ..read = p.read
            ..dirty = false
            ..updatedAt = p.updatedAt ?? DateTime.now());
        }
      });
    } on DioException {
      // offline — keep local
    }
  }

  /// Push any dirty library rows to backend (call on reconnect).
  Future<void> pushDirty() async {
    final dirtyRows =
        await _db.isar.library.filter().dirtyEqualTo(true).findAll();
    for (final r in dirtyRows) {
      try {
        if (r.present) {
          await _backend.addLibrary(r.mangaId);
          await _clearDirty(r.mangaId);
        } else {
          await _backend.removeLibrary(r.mangaId);
          await _db.isar.writeTxn(() => _db.isar.library.delete(r.isarId));
        }
      } on DioException {
        break; // still offline; try again later
      }
    }
  }
}
