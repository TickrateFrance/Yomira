import 'manga_source.dart';

/// Holds all content sources and offers per-source access plus merged queries.
class SourceRegistry {
  SourceRegistry(List<MangaSource> sources)
      : _byId = {for (final s in sources) s.id: s};

  final Map<SourceId, MangaSource> _byId;

  Iterable<MangaSource> get all => _byId.values;

  MangaSource of(SourceId id) {
    final s = _byId[id];
    if (s == null) throw StateError('No source registered for $id');
    return s;
  }

  /// Parse a globalId ("suwayomi:123") into (source, rawId).
  static (SourceId, String) parseGlobalId(String globalId) {
    final i = globalId.indexOf(':');
    if (i < 0) return (SourceId.suwayomi, globalId);
    final name = globalId.substring(0, i);
    final raw = globalId.substring(i + 1);
    final source = SourceId.values.firstWhere(
      (s) => s.name == name,
      orElse: () => SourceId.suwayomi,
    );
    return (source, raw);
  }

  /// Run a search across every source in parallel and merge. A source that
  /// errors is skipped (others still return).
  Future<List<UManga>> searchAll({
    required String title,
    List<String>? languages,
    List<String>? status,
  }) async {
    final results = await Future.wait(
      all.map((s) async {
        try {
          return await s.search(title: title, languages: languages, status: status);
        } catch (_) {
          return <UManga>[];
        }
      }),
    );
    return results.expand((e) => e).toList();
  }

  /// Progressive search: invokes [onUpdate] with the accumulated results each
  /// time a source finishes, so fast sources (MangaDex) render immediately and
  /// slow ones (Suwayomi with many extensions) fill in. Each source is capped
  /// by a timeout so one hanging source can't block the rest.
  Future<void> searchAllProgressive({
    required String title,
    List<String>? languages,
    List<String>? status,
    int page = 1,
    required void Function(List<UManga>) onUpdate,
  }) {
    // Rank merged results by how well each title matches the query, so the best
    // match surfaces at the top instead of being buried among other sources.
    return _progressive(
      (s) => s.search(title: title, languages: languages, status: status, page: page),
      (list) => onUpdate(_rankByRelevance(list, title)),
    );
  }

  /// Stable sort by relevance to [query] (exact > prefix > contains > word
  /// overlap). Keeps everything — only reorders.
  List<UManga> _rankByRelevance(List<UManga> list, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return list;
    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    int score(UManga m) {
      final t = m.title.toLowerCase();
      if (t == q) return 1000;
      if (t.startsWith(q)) return 800;
      if (t.contains(q)) return 600;
      var hits = 0;
      for (final tok in tokens) {
        if (t.contains(tok)) hits++;
      }
      if (tokens.isNotEmpty && hits == tokens.length) return 400;
      return hits * 50;
    }

    final indexed = [
      for (var i = 0; i < list.length; i++) (i, list[i], score(list[i]))
    ];
    indexed.sort((a, b) {
      final byScore = b.$3.compareTo(a.$3);
      return byScore != 0 ? byScore : a.$1.compareTo(b.$1); // stable on ties
    });
    return [for (final e in indexed) e.$2];
  }

  Future<void> popularAllProgressive({
    List<String>? languages,
    int page = 1,
    required void Function(List<UManga>) onUpdate,
  }) {
    return _progressive((s) => s.popular(languages: languages, page: page), onUpdate);
  }

  /// "Suggestions" for the Search landing view: popular across the source(s).
  Future<void> proposalsProgressive({
    List<String>? languages,
    int page = 1,
    required void Function(List<UManga>) onUpdate,
  }) {
    return popularAllProgressive(languages: languages, page: page, onUpdate: onUpdate);
  }

  Future<void> _progressive(
    Future<List<UManga>> Function(MangaSource) work,
    void Function(List<UManga>) onUpdate,
  ) async {
    final acc = <UManga>[];
    await Future.wait(all.map((s) async {
      try {
        final r = await work(s).timeout(const Duration(seconds: 30));
        acc.addAll(r);
      } catch (_) {
        // timeout / source error → contribute nothing
      }
      // Emit accumulated results so far (also clears the spinner on first done).
      onUpdate(List.of(acc));
    }));
  }

  /// Merged popular list across sources (errors skipped).
  Future<List<UManga>> popularAll({List<String>? languages}) async {
    final results = await Future.wait(
      all.map((s) async {
        try {
          return await s.popular(languages: languages);
        } catch (_) {
          return <UManga>[];
        }
      }),
    );
    // Interleave so the list isn't all-one-source-then-the-other.
    return _interleave(results);
  }

  List<UManga> _interleave(List<List<UManga>> lists) {
    final out = <UManga>[];
    var i = 0;
    bool any = true;
    while (any) {
      any = false;
      for (final l in lists) {
        if (i < l.length) {
          out.add(l[i]);
          any = true;
        }
      }
      i++;
    }
    return out;
  }
}
