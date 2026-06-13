import 'package:dio/dio.dart';

import 'manga_source.dart';

/// Suwayomi-Server (Tachidesk) source via its GraphQL API.
///
/// Suwayomi runs Mihon/Tachiyomi extensions, so this single source fronts many
/// underlying sites. Each Suwayomi "source" is one extension with a fixed
/// language, so we query only the EN/FR extensions when a language filter is
/// set. Page images are proxied by the Suwayomi server (relative URLs we make
/// absolute), so the phone never hits the origin site / Cloudflare.
///
/// Ids: Suwayomi manga/chapter ids are integers; our raw id is that int as a
/// string (globalId = "suwayomi:123").
class SuwayomiSource implements MangaSource {
  SuwayomiSource(this._dio, this._base, {required this.showNsfw});

  final Dio _dio;
  final String _base; // server root, e.g. http://host:4567

  /// Returns whether 18+ sources should be included (live from settings).
  final bool Function() showNsfw;

  List<_SuwSource>? _sourcesCache;
  DateTime _sourcesFetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, List<String>> _pageCache = {}; // chapterId -> page urls

  @override
  SourceId get id => SourceId.suwayomi;

  // ---- GraphQL plumbing ----

  Future<Map<String, dynamic>> _gql(String query, [Map<String, dynamic>? vars]) async {
    final res = await _dio.post('/api/graphql', data: {
      'query': query,
      if (vars != null) 'variables': vars,
    });
    final body = (res.data as Map).cast<String, dynamic>();
    if (body['errors'] != null) {
      throw DioException(
        requestOptions: res.requestOptions,
        message: 'Suwayomi GraphQL error: ${body['errors']}',
      );
    }
    return (body['data'] as Map).cast<String, dynamic>();
  }

  /// Make a Suwayomi-relative URL (thumbnail/page) absolute.
  String _abs(String url) =>
      url.startsWith('http') ? url : '$_base$url';

  // ---- sources (extensions) ----

  Future<List<_SuwSource>> _sources() async {
    // Short TTL cache so a freshly installed extension shows up within a few
    // seconds without restarting the app, while avoiding a query per source.
    final cached = _sourcesCache;
    if (cached != null &&
        DateTime.now().difference(_sourcesFetchedAt) < const Duration(seconds: 15)) {
      return cached;
    }
    final data = await _gql(r'''
      query { sources { nodes { id name lang isNsfw } } }
    ''');
    final nodes = (((data['sources'] as Map?)?['nodes']) as List?) ?? const [];
    _sourcesCache = nodes
        .map((n) => _SuwSource(
              id: '${(n as Map)['id']}',
              name: (n['name'] as String?) ?? '',
              lang: (n['lang'] as String?) ?? '',
              isNsfw: (n['isNsfw'] as bool?) ?? false,
            ))
        // Drop the built-in "Local source" (id 0) — no online content.
        .where((s) => s.id != '0')
        .toList();
    _sourcesFetchedAt = DateTime.now();
    return _sourcesCache!;
  }

  /// Sources matching the requested languages (or all if none requested).
  /// Sources whose language is "all" (multi-language extensions) are always
  /// included, since they carry EN/FR content too.
  Future<List<_SuwSource>> _sourcesFor(List<String>? languages) async {
    var all = await _sources();
    // Hide 18+ sources unless explicitly enabled in Settings.
    if (!showNsfw()) {
      all = all.where((s) => !s.isNsfw).toList();
    }
    if (languages == null || languages.isEmpty) return all;
    final set = languages.map((e) => e.toLowerCase()).toSet();
    final filtered = all.where((s) {
      final lang = s.lang.toLowerCase();
      return lang == 'all' || set.contains(lang);
    }).toList();
    return filtered.isEmpty ? all : filtered;
  }

  // ---- mapping ----

  UManga _toUManga(Map<String, dynamic> m, {String? lang, String? sourceName}) {
    final thumb = m['thumbnailUrl'] as String?;
    return UManga(
      source: SourceId.suwayomi,
      id: '${m['id']}',
      title: (m['title'] as String?) ?? 'Untitled',
      coverUrl: thumb == null ? null : _abs(thumb),
      description: (m['description'] as String?) ?? '',
      status: _statusOf(m['status'] as String?),
      year: null,
      tags: ((m['genre'] as List?) ?? const []).whereType<String>().toList(),
      languages: lang != null ? [lang] : const [],
      sourceName: sourceName,
      updatedAt: _uploadDate(m['latestUploadedChapter']),
    );
  }

  /// Parse latestUploadedChapter.uploadDate (ms since epoch, number or string).
  DateTime? _uploadDate(dynamic chapter) {
    if (chapter is! Map) return null;
    final raw = chapter['uploadDate'];
    final ms = raw is num ? raw.toInt() : int.tryParse('$raw');
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  String _statusOf(String? s) {
    switch (s) {
      case 'ONGOING':
        return 'ongoing';
      case 'COMPLETED':
      case 'PUBLISHING_FINISHED':
        return 'completed';
      case 'CANCELLED':
        return 'cancelled';
      case 'ON_HIATUS':
        return 'hiatus';
      default:
        return 'unknown';
    }
  }

  // ---- search / popular ----

  static const _fetchSourceMangaMutation = r'''
    mutation Fetch($source: LongString!, $type: FetchSourceMangaType!, $query: String, $page: Int!) {
      fetchSourceManga(input: { source: $source, type: $type, query: $query, page: $page }) {
        hasNextPage
        mangas { id title thumbnailUrl status genre latestUploadedChapter { uploadDate } }
      }
    }
  ''';

  Future<List<UManga>> _fetchAcrossSources({
    required String type,
    String? query,
    List<String>? languages,
    int page = 1,
    List<String>? sourceIds,
    void Function(List<UManga>)? onPartial,
  }) async {
    var sources = await _sourcesFor(languages);
    // Restrict to the picked sources when given — this is the big speed-up
    // (query 2 sources instead of ~25).
    if (sourceIds != null && sourceIds.isNotEmpty) {
      final keep = sourceIds.toSet();
      sources = sources.where((s) => keep.contains(s.id)).toList();
    }
    // Stream results out as each extension answers: fast sources render right
    // away instead of waiting up to 35s for a slow Cloudflare-protected one.
    final acc = <UManga>[];
    final results = await Future.wait(sources.map((s) async {
      try {
        final data = await _gql(_fetchSourceMangaMutation, {
          'source': s.id,
          'type': type,
          'query': query,
          'page': page,
        }).timeout(const Duration(seconds: 35)); // cap each source independently
        // 35s: Cloudflare first-solve via FlareSolverr/Byparr runs ~20-25s;
        // banned sites fast-fail, so this doesn't drag the batch.
        final mangas =
            (((data['fetchSourceManga'] as Map?)?['mangas']) as List?) ?? const [];
        final list = mangas
            .map((m) => _toUManga((m as Map).cast<String, dynamic>(),
                lang: s.lang, sourceName: s.name))
            .toList();
        if (onPartial != null && list.isNotEmpty) {
          acc.addAll(list);
          onPartial(List.of(acc));
        }
        return list;
      } catch (_) {
        // Slow/broken/timed-out source contributes nothing; others still return.
        return <UManga>[];
      }
    }));
    return results.expand((e) => e).toList();
  }

  @override
  Future<List<UManga>> search({
    required String title,
    List<String>? languages,
    List<String>? status,
    int page = 1,
    List<String>? sourceIds,
    void Function(List<UManga>)? onPartial,
  }) {
    return _fetchAcrossSources(
        type: 'SEARCH',
        query: title,
        languages: languages,
        page: page,
        sourceIds: sourceIds,
        onPartial: onPartial);
  }

  @override
  Future<List<UManga>> popular(
      {List<String>? languages,
      int page = 1,
      List<String>? sourceIds,
      void Function(List<UManga>)? onPartial}) {
    return _fetchAcrossSources(
        type: 'POPULAR',
        languages: languages,
        page: page,
        sourceIds: sourceIds,
        onPartial: onPartial);
  }

  @override
  Future<List<UManga>> latest(
      {List<String>? languages,
      int page = 1,
      List<String>? sourceIds,
      void Function(List<UManga>)? onPartial}) {
    // Sources that don't support LATEST just error and contribute nothing.
    return _fetchAcrossSources(
        type: 'LATEST',
        languages: languages,
        page: page,
        sourceIds: sourceIds,
        onPartial: onPartial);
  }

  @override
  Future<List<SourceInfo>> listSources({List<String>? languages}) async {
    final sources = await _sourcesFor(languages);
    return sources
        .map((s) => SourceInfo(id: s.id, name: s.name, lang: s.lang, isNsfw: s.isNsfw))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  // ---- detail / languages / feed ----

  @override
  Future<UManga> detail(String id) async {
    final data = await _gql(r'''
      query Manga($id: Int!) {
        manga(id: $id) {
          id title thumbnailUrl description status genre
          source { lang name }
        }
      }
    ''', {'id': int.parse(id)});
    final m = (data['manga'] as Map).cast<String, dynamic>();
    final src = (m['source'] as Map?);
    final lang = src?['lang'] as String?;
    final name = src?['name'] as String?;
    return _toUManga(m, lang: lang, sourceName: name);
  }

  @override
  Future<List<String>> languages(String id) async {
    final m = await detail(id);
    return m.languages;
  }

  @override
  Future<List<UChapter>> feed(String mangaId, String language) async {
    // fetchChapters pulls the latest chapter list from the source.
    final data = await _gql(r'''
      mutation Chapters($id: Int!) {
        fetchChapters(input: { mangaId: $id }) {
          chapters { id name chapterNumber scanlator pageCount }
        }
      }
    ''', {'id': int.parse(mangaId)});
    final list =
        (((data['fetchChapters'] as Map?)?['chapters']) as List?) ?? const [];

    final chapters = list.map((c) {
      final m = (c as Map).cast<String, dynamic>();
      final num = m['chapterNumber'];
      return UChapter(
        source: SourceId.suwayomi,
        id: '${m['id']}',
        number: num == null ? null : _fmtNumber(num),
        title: (m['name'] as String?) ?? '',
        language: language,
        pages: (m['pageCount'] as int?) ?? 0,
        group: m['scanlator'] as String?,
      );
    }).toList();

    chapters.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return chapters;
  }

  String _fmtNumber(dynamic n) {
    final d = (n is num) ? n.toDouble() : double.tryParse('$n');
    if (d == null) return '$n';
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  }

  // ---- pages ----

  Future<List<String>> _pages(String chapterId) async {
    final cached = _pageCache[chapterId];
    if (cached != null) return cached;
    final data = await _gql(r'''
      mutation Pages($id: Int!) {
        fetchChapterPages(input: { chapterId: $id }) {
          pages
        }
      }
    ''', {'id': int.parse(chapterId)});
    final pages =
        (((data['fetchChapterPages'] as Map?)?['pages']) as List?) ?? const [];
    final urls = pages.whereType<String>().map(_abs).toList();
    _pageCache[chapterId] = urls;
    return urls;
  }

  @override
  Future<int> pageCount(String chapterId, {required bool dataSaver}) async {
    final pages = await _pages(chapterId);
    return pages.length;
  }

  @override
  Future<String> pageUrl(
    String chapterId,
    int index, {
    required bool dataSaver,
    bool refresh = false,
  }) async {
    if (refresh) _pageCache.remove(chapterId);
    final pages = await _pages(chapterId);
    return pages[index];
  }
}

class _SuwSource {
  _SuwSource({
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
