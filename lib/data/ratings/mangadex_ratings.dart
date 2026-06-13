import 'package:dio/dio.dart';

import '../../core/config.dart';

/// Canonical manga info from the public MangaDex API, matched by title:
/// rating, original language (for content type) and genres. Read-only, cached.
class MdInfo {
  MdInfo({this.rating, this.originalLanguage, this.genres = const [], this.coverUrl});

  /// 0–10 rating, or null.
  final double? rating;

  /// Public MangaDex cover thumbnail URL, or null. Safe to show anywhere
  /// (no auth) - used for the Discord Rich Presence cover art.
  final String? coverUrl;

  /// MangaDex originalLanguage: "ja" (manga), "ko" (manhwa), "zh"/"zh-hk" (manhua)…
  final String? originalLanguage;

  /// English genre names (MangaDex "genre" tags).
  final List<String> genres;

  /// Content-type label from the original language, or null if unknown.
  String? get contentType {
    switch (originalLanguage) {
      case 'ja':
        return 'Manga';
      case 'ko':
        return 'Manhwa';
      case 'zh':
      case 'zh-hk':
      case 'zh-ro':
        return 'Manhua';
      default:
        return null;
    }
  }
}

class MangaDexRatings {
  MangaDexRatings(this._dio);

  final Dio _dio;
  final Map<String, MdInfo?> _cache = {};

  /// Full info for [title], or null if MangaDex has no match. Best-effort.
  Future<MdInfo?> infoFor(String title) async {
    final key = title.toLowerCase().trim();
    if (key.isEmpty) return null;
    if (_cache.containsKey(key)) return _cache[key];

    try {
      final search = await _dio.get('/manga', queryParameters: {
        'title': title,
        'limit': 1,
        'order[relevance]': 'desc',
        'includes[]': 'cover_art',
      });
      final data = ((search.data as Map)['data'] as List?) ?? const [];
      if (data.isEmpty) return _cache[key] = null;

      final manga = (data.first as Map).cast<String, dynamic>();
      final id = manga['id'] as String;
      final attr = (manga['attributes'] as Map?)?.cast<String, dynamic>() ?? {};
      final lang = attr['originalLanguage'] as String?;

      // Public cover thumbnail (from the cover_art relationship).
      String? coverUrl;
      for (final rel in (manga['relationships'] as List?) ?? const []) {
        final rm = (rel as Map).cast<String, dynamic>();
        if (rm['type'] != 'cover_art') continue;
        final fn = ((rm['attributes'] as Map?)?['fileName']) as String?;
        if (fn != null && fn.isNotEmpty) {
          coverUrl = '${AppConfig.mangadexUploadsBase}/covers/$id/$fn.512.jpg';
        }
        break;
      }

      final genres = <String>[];
      for (final t in (attr['tags'] as List?) ?? const []) {
        final ta = ((t as Map)['attributes'] as Map?)?.cast<String, dynamic>();
        if (ta == null || ta['group'] != 'genre') continue;
        final name = (ta['name'] as Map?)?['en'] as String?;
        if (name != null && name.isNotEmpty) genres.add(name);
      }

      double? rating;
      try {
        final stats = await _dio.get('/statistics/manga/$id');
        final map = ((stats.data as Map)['statistics'] as Map?)?[id] as Map?;
        final r = (map?['rating'] as Map?);
        final v = r?['bayesian'] ?? r?['average'];
        if (v is num && v > 0) rating = v.toDouble();
      } catch (_) {}

      return _cache[key] =
          MdInfo(rating: rating, originalLanguage: lang, genres: genres, coverUrl: coverUrl);
    } catch (_) {
      return _cache[key] = null;
    }
  }

  /// Convenience: just the rating (0–10), or null.
  Future<double?> ratingFor(String title) async => (await infoFor(title))?.rating;

  List<String>? _allTags;

  /// Lowercase tag name -> MangaDex tag UUID (filled by [allTags]).
  final Map<String, String> _tagIds = {};

  /// Every tag MangaDex defines (genres, themes, formats), lowercase English
  /// names, fetched once from the public GET /manga/tag endpoint. Best-effort:
  /// returns an empty list when offline.
  Future<List<String>> allTags() async {
    final cached = _allTags;
    if (cached != null) return cached;
    try {
      final res = await _dio.get('/manga/tag');
      final data = ((res.data as Map)['data'] as List?) ?? const [];
      final names = <String>[];
      for (final t in data) {
        final tm = (t as Map).cast<String, dynamic>();
        final ta = (tm['attributes'] as Map?)?.cast<String, dynamic>();
        final name = ((ta?['name'] as Map?)?['en'] as String?)?.trim();
        final id = tm['id'] as String?;
        if (name == null || name.isEmpty) continue;
        names.add(name.toLowerCase());
        if (id != null) _tagIds[name.toLowerCase()] = id;
      }
      names.sort();
      return _allTags = names;
    } catch (_) {
      return const [];
    }
  }

  /// Titles matching ALL [tagNames] on MangaDex (most-followed first), with a
  /// public cover. Tag names that MangaDex doesn't know are ignored. The result
  /// is display-only: the caller matches titles back to its own sources.
  Future<List<({String title, String? coverUrl})>> searchByTags(
    Set<String> tagNames, {
    String? title,
    int limit = 30,
  }) async {
    await allTags(); // make sure the name -> id map is loaded
    final ids = <String>[
      for (final n in tagNames)
        if (_tagIds[n.toLowerCase()] != null) _tagIds[n.toLowerCase()]!,
    ];
    if (ids.isEmpty) return const [];
    try {
      final res = await _dio.get('/manga', queryParameters: {
        'includedTags[]': ids,
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        'limit': limit,
        'order[followedCount]': 'desc',
        'includes[]': 'cover_art',
      });
      final data = ((res.data as Map)['data'] as List?) ?? const [];
      final out = <({String title, String? coverUrl})>[];
      for (final m in data) {
        final mm = (m as Map).cast<String, dynamic>();
        final attr = (mm['attributes'] as Map?)?.cast<String, dynamic>() ?? {};
        final titles = (attr['title'] as Map?)?.cast<String, dynamic>() ?? {};
        final name = (titles['en'] ??
                (titles.isNotEmpty ? titles.values.first : null)) as String?;
        if (name == null || name.isEmpty) continue;
        String? coverUrl;
        final id = mm['id'] as String?;
        for (final rel in (mm['relationships'] as List?) ?? const []) {
          final rm = (rel as Map).cast<String, dynamic>();
          if (rm['type'] != 'cover_art') continue;
          final fn = ((rm['attributes'] as Map?)?['fileName']) as String?;
          if (fn != null && fn.isNotEmpty && id != null) {
            coverUrl = '${AppConfig.mangadexUploadsBase}/covers/$id/$fn.512.jpg';
          }
          break;
        }
        out.add((title: name, coverUrl: coverUrl));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}
