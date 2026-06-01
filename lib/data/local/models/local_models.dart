import 'package:isar/isar.dart';

part 'local_models.g.dart';

/// Cached manga metadata so library/history render offline.
@Collection(accessor: 'cachedManga')
class CachedManga {
  Id get isarId => fastHash(mangaId);

  @Index(unique: true, replace: true)
  late String mangaId;

  late String title;
  String? coverUrl;
  String description = '';
  String status = 'unknown';
  int? year;
  List<String> tags = const [];

  DateTime updatedAt = DateTime.now();
}

/// Local mirror of reading progress (also synced to backend).
@Collection(accessor: 'progress')
class LocalProgress {
  Id get isarId => fastHash('$mangaId::$chapterId');

  @Index()
  late String mangaId;

  @Index(unique: true, replace: true)
  late String chapterId;

  /// MangaDex chapter number as a string ("10", "10.5"). Stored so History can
  /// show the last chapter read without re-fetching the feed.
  String? chapterNumber;

  /// Translated language of the chapter — needed to re-fetch the feed when
  /// resuming ("Continue reading") from History.
  String? language;

  int lastPage = 0;
  bool read = false;

  /// Set when changed offline and not yet pushed to backend.
  bool dirty = false;

  DateTime updatedAt = DateTime.now();
}

/// Library membership mirror.
@Collection(accessor: 'library')
class LocalLibrary {
  Id get isarId => fastHash(mangaId);

  @Index(unique: true, replace: true)
  late String mangaId;

  DateTime addedAt = DateTime.now();

  /// add/remove pending push to backend.
  bool dirty = false;

  /// true = pending add, false = pending remove (when dirty).
  bool present = true;
}

/// History mirror: last time a manga was opened.
@Collection(accessor: 'history')
class LocalHistory {
  Id get isarId => fastHash(mangaId);

  @Index(unique: true, replace: true)
  late String mangaId;

  @Index()
  DateTime lastReadAt = DateTime.now();
}

/// A downloaded chapter for offline reading.
@Collection(accessor: 'downloads')
class DownloadedChapter {
  Id get isarId => fastHash(chapterId);

  @Index(unique: true, replace: true)
  late String chapterId;

  late String mangaId;

  /// Absolute file paths of the downloaded page images, in order.
  List<String> pagePaths = const [];

  int pageCount = 0;
  DateTime downloadedAt = DateTime.now();
}

/// FNV-1a 64-bit string hash → stable Isar Id from a string key.
int fastHash(String string) {
  var hash = 0xcbf29ce484222325;
  for (var i = 0; i < string.length; i++) {
    hash ^= string.codeUnitAt(i);
    hash *= 0x100000001b3;
  }
  return hash;
}
