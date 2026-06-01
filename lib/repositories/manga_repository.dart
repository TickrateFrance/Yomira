import 'package:isar/isar.dart';

import '../data/local/isar_db.dart';
import '../data/local/models/local_models.dart';
import '../data/sources/manga_source.dart';
import '../data/sources/source_registry.dart';

/// Search + detail + feed across all sources, with metadata caching for offline.
/// All ids passed in/out are **globalIds** ("mangadex:uuid" / "comick:hid").
class MangaRepository {
  MangaRepository(this._sources, this._db);

  final SourceRegistry _sources;
  final LocalDb _db;

  Future<List<UManga>> search({
    required String title,
    List<String>? status,
    List<String>? languages,
  }) {
    return _sources.searchAll(title: title, status: status, languages: languages);
  }

  Future<List<UManga>> popular({List<String>? languages}) {
    return _sources.popularAll(languages: languages);
  }

  /// Underlying sources available (for the desktop source picker).
  Future<List<SourceInfo>> listSources({List<String>? languages}) {
    return _sources.listSources(languages: languages);
  }

  /// Progressive variants: [onUpdate] fires with accumulated results as each
  /// source returns, so the UI isn't blocked waiting on the slowest source.
  /// [sourceIds] restricts the query to those sources (faster).
  Future<void> searchProgressive({
    required String title,
    List<String>? status,
    List<String>? languages,
    int page = 1,
    List<String>? sourceIds,
    required void Function(List<UManga>) onUpdate,
  }) {
    return _sources.searchAllProgressive(
        title: title,
        status: status,
        languages: languages,
        page: page,
        sourceIds: sourceIds,
        onUpdate: onUpdate);
  }

  Future<void> popularProgressive({
    List<String>? languages,
    int page = 1,
    List<String>? sourceIds,
    required void Function(List<UManga>) onUpdate,
  }) {
    return _sources.popularAllProgressive(
        languages: languages, page: page, sourceIds: sourceIds, onUpdate: onUpdate);
  }

  /// Latest-updated titles (the "Latest" / new-releases view).
  Future<void> latestProgressive({
    List<String>? languages,
    int page = 1,
    List<String>? sourceIds,
    required void Function(List<UManga>) onUpdate,
  }) {
    return _sources.latestAllProgressive(
        languages: languages, page: page, sourceIds: sourceIds, onUpdate: onUpdate);
  }

  /// Blended suggestions for the landing view.
  Future<void> proposalsProgressive({
    List<String>? languages,
    int page = 1,
    List<String>? sourceIds,
    required void Function(List<UManga>) onUpdate,
  }) {
    return _sources.proposalsProgressive(
        languages: languages, page: page, sourceIds: sourceIds, onUpdate: onUpdate);
  }

  Future<UManga> detail(String globalId) async {
    final (source, rawId) = SourceRegistry.parseGlobalId(globalId);
    final manga = await _sources.of(source).detail(rawId);
    await _cacheManga(manga);
    return manga;
  }

  Future<List<String>> languages(String globalId) {
    final (source, rawId) = SourceRegistry.parseGlobalId(globalId);
    return _sources.of(source).languages(rawId);
  }

  Future<List<UChapter>> feed(String globalId, String language) {
    final (source, rawId) = SourceRegistry.parseGlobalId(globalId);
    return _sources.of(source).feed(rawId, language);
  }

  /// Cached manga (for offline library/history rendering). Keyed by globalId.
  Future<CachedManga?> cached(String globalId) async {
    return _db.isar.cachedManga.where().mangaIdEqualTo(globalId).findFirst();
  }

  /// Reading summary for a manga: how many chapters marked read and the
  /// highest chapter number reached. Used by the History list.
  Future<ProgressSummary> progressSummary(String globalId) async {
    final rows =
        await _db.isar.progress.where().mangaIdEqualTo(globalId).findAll();
    final readRows = rows.where((r) => r.read).toList();
    double? maxNum;
    for (final r in rows) {
      final n = double.tryParse(r.chapterNumber ?? '');
      if (n != null && (maxNum == null || n > maxNum)) maxNum = n;
    }
    String? last;
    if (maxNum != null) {
      last = maxNum == maxNum.roundToDouble()
          ? maxNum.toInt().toString()
          : maxNum.toString();
    }
    return ProgressSummary(readCount: readRows.length, lastChapter: last);
  }

  /// The most recently-read chapter for a manga (by updatedAt), used to resume
  /// from History. Null if there's no progress yet.
  Future<ResumeTarget?> resumeTarget(String mangaId) async {
    final rows =
        await _db.isar.progress.where().mangaIdEqualTo(mangaId).findAll();
    if (rows.isEmpty) return null;
    rows.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final last = rows.first;
    return ResumeTarget(
      chapterId: last.chapterId,
      chapterNumber: last.chapterNumber,
      language: last.language,
      lastPage: last.lastPage,
      read: last.read,
    );
  }

  Future<void> _cacheManga(UManga m) async {
    final entry = CachedManga()
      ..mangaId = m.globalId
      ..title = m.title
      ..coverUrl = m.coverUrl
      ..sourceName = m.sourceName
      ..description = m.description
      ..status = m.status
      ..year = m.year
      ..tags = m.tags
      ..updatedAt = DateTime.now();
    await _db.isar.writeTxn(() async {
      await _db.isar.cachedManga.put(entry);
    });
  }
}

/// Per-manga reading summary for the History list.
class ProgressSummary {
  ProgressSummary({required this.readCount, this.lastChapter});

  final int readCount;
  final String? lastChapter;
}

/// Where to resume a manga from History.
class ResumeTarget {
  ResumeTarget({
    required this.chapterId,
    required this.chapterNumber,
    required this.language,
    required this.lastPage,
    required this.read,
  });

  final String chapterId; // globalId of the last-read chapter
  final String? chapterNumber;
  final String? language; // its translated language (for the feed)
  final int lastPage;
  final bool read; // whether that chapter was finished
}
