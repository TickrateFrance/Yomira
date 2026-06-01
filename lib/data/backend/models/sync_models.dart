/// Backend sync DTOs: progress, library, history.
class ProgressEntry {
  ProgressEntry({
    required this.mangaId,
    required this.chapterId,
    required this.lastPage,
    required this.read,
    this.chapterNumber,
    this.language,
    this.title,
    this.coverUrl,
    this.updatedAt,
  });

  final String mangaId;
  final String chapterId;
  final int lastPage;
  final bool read;
  final String? chapterNumber;
  final String? language;
  // Manga snapshot, only sent on PUT so the backend can store it on history.
  // Null when reading progress back from the server.
  final String? title;
  final String? coverUrl;
  final DateTime? updatedAt;

  Map<String, dynamic> toPutBody() => {
        'mangaId': mangaId,
        'chapterId': chapterId,
        'lastPage': lastPage,
        'read': read,
        if (chapterNumber != null) 'chapterNumber': chapterNumber,
        if (language != null) 'language': language,
        if (title != null && title!.isNotEmpty) 'title': title,
        if (coverUrl != null && coverUrl!.isNotEmpty) 'coverUrl': coverUrl,
      };

  factory ProgressEntry.fromJson(Map<String, dynamic> json) => ProgressEntry(
        mangaId: json['mangaId'] as String,
        chapterId: json['chapterId'] as String,
        lastPage: (json['lastPage'] as int?) ?? 0,
        read: (json['read'] as bool?) ?? false,
        chapterNumber: json['chapterNumber'] as String?,
        language: json['language'] as String?,
        updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? ''),
      );
}

class LibraryEntry {
  LibraryEntry({required this.mangaId, this.addedAt});

  final String mangaId;
  final DateTime? addedAt;

  factory LibraryEntry.fromJson(Map<String, dynamic> json) => LibraryEntry(
        mangaId: json['mangaId'] as String,
        addedAt: DateTime.tryParse((json['addedAt'] as String?) ?? ''),
      );
}

class HistoryEntry {
  HistoryEntry({required this.mangaId, this.title, this.coverUrl, this.lastReadAt});

  final String mangaId;
  final String? title;
  final String? coverUrl;
  final DateTime? lastReadAt;

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        mangaId: json['mangaId'] as String,
        title: json['title'] as String?,
        coverUrl: json['coverUrl'] as String?,
        lastReadAt: DateTime.tryParse((json['lastReadAt'] as String?) ?? ''),
      );
}
