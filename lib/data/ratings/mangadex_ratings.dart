import 'package:dio/dio.dart';

/// Canonical manga info from the public MangaDex API, matched by title:
/// rating, original language (for content type) and genres. Read-only, cached.
class MdInfo {
  MdInfo({this.rating, this.originalLanguage, this.genres = const []});

  /// 0–10 rating, or null.
  final double? rating;

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
      });
      final data = ((search.data as Map)['data'] as List?) ?? const [];
      if (data.isEmpty) return _cache[key] = null;

      final manga = (data.first as Map).cast<String, dynamic>();
      final id = manga['id'] as String;
      final attr = (manga['attributes'] as Map?)?.cast<String, dynamic>() ?? {};
      final lang = attr['originalLanguage'] as String?;

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

      return _cache[key] = MdInfo(rating: rating, originalLanguage: lang, genres: genres);
    } catch (_) {
      return _cache[key] = null;
    }
  }

  /// Convenience: just the rating (0–10), or null.
  Future<double?> ratingFor(String title) async => (await infoFor(title))?.rating;
}
