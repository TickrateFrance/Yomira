import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/sources/manga_source.dart';
import '../../repositories/auth_repository.dart';
import '../../state/providers.dart';
import '../widgets/async_views.dart';
import '../widgets/manga_cover.dart';

/// "Discover" tab — a CS:GO-style case-opening reel that spins and lands on a
/// recommendation. No history → a random pick; otherwise biased toward titles
/// that share tags with what you've read.
class RecommendScreen extends ConsumerStatefulWidget {
  const RecommendScreen({super.key});

  @override
  ConsumerState<RecommendScreen> createState() => _RecommendScreenState();
}

class _RecommendScreenState extends ConsumerState<RecommendScreen> {
  static const double _tile = 124; // tile width incl. spacing
  static const int _reelLen = 48;
  static const int _winnerIndex = _reelLen - 6;

  final _rng = Random();
  final _scroll = ScrollController();

  bool _loading = true;
  String? _error;
  List<UManga> _pool = const [];
  List<UManga> _reel = const [];

  bool _spinning = false;
  UManga? _winner;

  @override
  void initState() {
    super.initState();
    _prepare();
    ref.read(tabRefreshProvider).register(3, () async => _spin());
  }

  @override
  void dispose() {
    ref.read(tabRefreshProvider).unregister(3);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(mangaRepositoryProvider);
      final raw = await repo.popular(languages: const ['en', 'fr']);
      final seen = <String>{};
      final pool = raw
          .where((m) => m.coverUrl != null && seen.add(m.title.toLowerCase()))
          .toList();
      if (pool.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Nothing to recommend yet — try again later.';
        });
        return;
      }
      _pool = pool;
      _reel = _randomReel();
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = describeBackendError(e);
      });
    }
  }

  List<UManga> _randomReel() =>
      [for (var i = 0; i < _reelLen; i++) _pool[_rng.nextInt(_pool.length)]];

  String _norm(String t) =>
      t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  /// Taste profile from cached metadata: tag -> weight. Recent history counts
  /// more than old history; library favorites are the strongest signal. Also
  /// returns the normalized titles the user already knows (to skip them).
  Future<(Map<String, double>, Set<String>)> _tasteProfile() async {
    final lib = ref.read(libraryRepositoryProvider);
    final repo = ref.read(mangaRepositoryProvider);
    final weights = <String, double>{};
    final known = <String>{};

    final rows = await lib.localHistory(limit: 50);
    for (var i = 0; i < rows.length; i++) {
      final c = await repo.cached(rows[i].mangaId);
      if (c == null) continue;
      known.add(_norm(c.title));
      // Newest entry weighs ~2.0, oldest ~1.0.
      final w = 1.0 + (rows.length - i) / rows.length;
      for (final t in c.tags) {
        final k = t.toLowerCase();
        weights[k] = (weights[k] ?? 0) + w;
      }
    }
    for (final row in (await lib.localLibrary()).where((e) => e.present)) {
      final c = await repo.cached(row.mangaId);
      if (c == null) continue;
      known.add(_norm(c.title));
      for (final t in c.tags) {
        final k = t.toLowerCase();
        weights[k] = (weights[k] ?? 0) + 2.0;
      }
    }
    return (weights, known);
  }

  /// Choose the winner: prefer titles the user hasn't read, scored by the
  /// weighted overlap between their tags and the taste profile.
  Future<UManga> _pickWinner() async {
    final (weights, known) = await _tasteProfile();

    // Skip what's already in history/library (unless that empties the pool).
    var candidates = _pool.where((m) => !known.contains(_norm(m.title))).toList();
    if (candidates.isEmpty) candidates = _pool;
    if (weights.isEmpty) return candidates[_rng.nextInt(candidates.length)];

    final repo = ref.read(mangaRepositoryProvider);
    final sample = (candidates.toList()..shuffle(_rng)).take(16).toList();
    UManga best = sample.first;
    var bestScore = -1.0;
    await Future.wait(sample.map((m) async {
      try {
        // Tags may already be on the search result (genre now fetched);
        // fall back to a detail fetch when they're missing.
        var tags = m.tags;
        if (tags.isEmpty) {
          final d = await repo.detail(m.globalId).timeout(const Duration(seconds: 8));
          tags = d.tags;
        }
        var score = 0.0;
        for (final t in tags) {
          score += weights[t.toLowerCase()] ?? 0;
        }
        if (score > bestScore) {
          bestScore = score;
          best = m;
        }
      } catch (_) {}
    }));
    // No overlap found anywhere -> fall back to random unknown title.
    return bestScore > 0 ? best : candidates[_rng.nextInt(candidates.length)];
  }

  Future<void> _spin() async {
    if (_spinning || _pool.isEmpty) return;
    setState(() {
      _spinning = true;
      _winner = null;
    });

    final winner = await _pickWinner();
    if (!mounted) return;

    final reel = _randomReel();
    reel[_winnerIndex] = winner;
    setState(() => _reel = reel);

    // Let the new reel lay out, reset to start, then animate to the winner.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scroll.hasClients) {
      setState(() => _spinning = false);
      return;
    }
    _scroll.jumpTo(0);
    final vp = _scroll.position.viewportDimension;
    // Land the winner under the center marker, with a little random offset.
    final jitter = (_rng.nextDouble() - 0.5) * (_tile * 0.5);
    final target = (_winnerIndex * _tile + _tile / 2 - vp / 2 + jitter)
        .clamp(0.0, _scroll.position.maxScrollExtent);

    await _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 4500),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    setState(() {
      _winner = winner;
      _spinning = false;
    });
  }

  void _open(UManga m) => context.push('/manga/${Uri.encodeComponent(m.globalId)}');

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppBar(title: const Text('Discover'), automaticallyImplyLeading: false),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: _prepare);

    final scheme = Theme.of(context).colorScheme;
    // Constrain to a centered column on wide/desktop screens. A full-width reel
    // makes the viewport so wide the spin can't scroll far enough to land the
    // winner under the marker (maxScrollExtent clamp) — this keeps it correct
    // and centered. Phones (narrower than the cap) are unaffected.
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          children: [
            const SizedBox(height: 12),
        // ---- the reel ----
        SizedBox(
          height: 188,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ListView.builder(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemExtent: _tile,
                itemCount: _reel.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: MangaCover(url: _reel[i].coverUrl),
                  ),
                ),
              ),
              // edge fades
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.bg,
                          AppTheme.bg.withValues(alpha: 0.0),
                          AppTheme.bg.withValues(alpha: 0.0),
                          AppTheme.bg,
                        ],
                        stops: const [0.0, 0.12, 0.88, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              // center marker — full-height bar with arrows at both ends.
              IgnorePointer(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 3,
                      height: 176,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: Icon(Icons.arrow_drop_down, color: scheme.primary, size: 30),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Icon(Icons.arrow_drop_up, color: scheme.primary, size: 30),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---- result / action ----
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                if (_winner != null && !_spinning) _winnerCard(_winner!) else _hint(),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _spinning ? null : _spin,
                  icon: Icon(_spinning ? Icons.hourglass_top : Icons.casino),
                  label: Text(_spinning ? 'Rolling…' : 'Discover'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
          ],
        ),
      ),
    );
  }

  Widget _hint() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        'Spin to get a recommendation.\nWith reading history, picks lean toward your taste.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _winnerCard(UManga m) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SizedBox(
            width: 150,
            height: 214,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: MangaCover(url: m.coverUrl),
            ),
          ),
          const SizedBox(height: 12),
          Text(m.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(m.displayLabel,
              style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _open(m),
            icon: const Icon(Icons.menu_book),
            label: const Text('Open'),
          ),
        ],
      ),
    );
  }
}
