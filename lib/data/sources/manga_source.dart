/// Source-agnostic models + the [MangaSource] interface. Each content provider
/// implements [MangaSource] and maps its own payloads to these unified types so
/// the UI and reader work the same regardless of source.
library;

/// Identifies a content provider. The app sources everything through Suwayomi
/// (which itself runs many site extensions); the per-extension name is carried
/// on [UManga.sourceName].
enum SourceId { suwayomi }

extension SourceIdLabel on SourceId {
  String get label => switch (this) {
        SourceId.suwayomi => 'Suwayomi',
      };
}

/// A manga/manhwa/manhua from any source.
class UManga {
  UManga({
    required this.source,
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.description,
    required this.status,
    required this.year,
    required this.tags,
    required this.languages,
    this.rating,
    this.follows,
    this.sourceName,
    this.updatedAt,
  });

  final SourceId source;
  final String id; // raw, source-specific id
  final String title;
  final String? coverUrl;
  final String description;
  final String status;
  final int? year;
  final List<String> tags;
  final List<String> languages; // available chapter languages (best-effort)
  final double? rating; // 0..10 if known
  final int? follows;

  /// Underlying provider name behind an aggregator (e.g. Suwayomi → "Webtoon",
  /// "Thunder Scans"). Null for direct sources like MangaDex.
  final String? sourceName;

  /// When the latest chapter was uploaded at the source (best-effort; null if
  /// the source/Suwayomi hasn't reported it). Drives the "recently updated" badge.
  final DateTime? updatedAt;

  /// Badge label: the real underlying source when known, else the source name.
  String get displayLabel =>
      (sourceName != null && sourceName!.isNotEmpty) ? sourceName! : source.label;

  /// Stable cross-source key for storage/sync: "mangadex:uuid" / "suwayomi:id".
  String get globalId => '${source.name}:$id';

  static String makeGlobalId(SourceId source, String id) => '${source.name}:$id';
}

/// A chapter from any source.
class UChapter {
  UChapter({
    required this.source,
    required this.id,
    required this.number,
    required this.title,
    required this.language,
    required this.pages,
    required this.group,
  });

  final SourceId source;
  final String id;
  final String? number; // "10", "10.5"
  final String title;
  final String language;
  final int pages; // 0 if unknown until opened
  final String? group;

  String get globalId => '${source.name}:$id';

  String get label {
    final num = number != null ? 'Ch. $number' : 'Oneshot';
    return title.isEmpty ? num : '$num — $title';
  }

  double get sortKey => double.tryParse(number ?? '') ?? double.infinity;
}

/// One selectable content provider behind the aggregator (e.g. a Suwayomi
/// extension: "AnimeSama", "Mangas-Origines").
class SourceInfo {
  SourceInfo({
    required this.id,
    required this.name,
    required this.lang,
    required this.isNsfw,
  });
  final String id;
  final String name;
  final String lang;
  final bool isNsfw;
}

/// Implemented by every content provider.
abstract class MangaSource {
  SourceId get id;

  /// Title search. [languages] restricts to titles having chapters in any of
  /// those languages (server-side when supported). [page] is 1-based.
  /// [sourceIds] (optional) restricts the query to those underlying sources —
  /// far faster than hitting every source.
  Future<List<UManga>> search({
    required String title,
    List<String>? languages,
    List<String>? status,
    int page = 1,
    List<String>? sourceIds,
  });

  /// Default discovery list (most-followed / popular). [page] is 1-based.
  Future<List<UManga>> popular({
    List<String>? languages,
    int page = 1,
    List<String>? sourceIds,
  });

  /// Latest updates (most recently updated titles). [page] is 1-based.
  Future<List<UManga>> latest({
    List<String>? languages,
    int page = 1,
    List<String>? sourceIds,
  });

  /// The underlying sources available (for a source picker). [languages]
  /// narrows to matching-language sources.
  Future<List<SourceInfo>> listSources({List<String>? languages});

  /// Full detail for one manga.
  Future<UManga> detail(String id);

  /// Available chapter languages for a manga (best-effort).
  Future<List<String>> languages(String id);

  /// Chapters for a manga in one language, ascending by chapter number.
  Future<List<UChapter>> feed(String mangaId, String language);

  /// Page count for a chapter at the given quality.
  Future<int> pageCount(String chapterId, {required bool dataSaver});

  /// URL for one page. [refresh] forces re-resolution (e.g. after a CDN 403 on
  /// sources with expiring URLs like MangaDex at-home).
  Future<String> pageUrl(
    String chapterId,
    int index, {
    required bool dataSaver,
    bool refresh = false,
  });
}
