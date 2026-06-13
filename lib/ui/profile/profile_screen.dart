import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/local/models/local_models.dart';
import '../../data/local/reading_time_store.dart';
import '../../data/ratings/mangadex_ratings.dart';
import '../../repositories/manga_repository.dart';
import '../../state/providers.dart';
import '../widgets/async_views.dart';
import '../widgets/manga_cover.dart';
import '../widgets/manga_poster.dart';

/// User profile: account header, library (favorites) and reading history.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late Future<_ProfileData> _future;

  /// Canonical MangaDex info per mangaId (for accurate genre/content-type stats).
  final Map<String, MdInfo> _md = {};

  @override
  void initState() {
    super.initState();
    _future = _loadLocal(); // instant from cache
    _sync(); // refresh from backend + heal in the background
  }

  /// Fast: build from the local cache only, no network.
  Future<_ProfileData> _loadLocal() async {
    final lib = ref.read(libraryRepositoryProvider);
    final repo = ref.read(mangaRepositoryProvider);

    final favorites = <_Item>[];
    for (final row in (await lib.localLibrary()).where((e) => e.present)) {
      favorites.add(_Item(row.mangaId, await repo.cached(row.mangaId), null));
    }
    final history = <_Item>[];
    for (final h in await lib.localHistory(limit: 30)) {
      history.add(_Item(h.mangaId, await repo.cached(h.mangaId),
          await repo.progressSummary(h.mangaId),
          lastReadAt: h.lastReadAt));
    }
    final username = ref.read(authControllerProvider.notifier).username;
    final progressRows = await repo.allProgress();
    final timeByDay = await ReadingTimeStore().all();
    return _ProfileData(
        username: username,
        favorites: favorites,
        history: history,
        progressRows: progressRows,
        timeByDay: timeByDay);
  }

  Future<void> _sync() async {
    try {
      final lib = ref.read(libraryRepositoryProvider);
      final repo = ref.read(mangaRepositoryProvider);
      final md = ref.read(mangadexRatingsProvider);
      await lib.pullFromBackend();

      final histRows = await lib.localHistory(limit: 30);
      final favRows = (await lib.localLibrary()).where((e) => e.present).toList();

      // Heal missing titles/covers so we have a title to query MangaDex with.
      for (final h in histRows) {
        final c = await repo.cached(h.mangaId);
        if (c == null || c.title.isEmpty) {
          try {
            await repo.detail(h.mangaId);
          } catch (_) {}
        }
      }

      // Fetch canonical MangaDex info per title (skip ones with no match).
      final ids = {...histRows.map((e) => e.mangaId), ...favRows.map((e) => e.mangaId)};
      for (final id in ids) {
        if (_md.containsKey(id)) continue;
        final title = (await repo.cached(id))?.title;
        if (title == null || title.isEmpty) continue;
        final info = await md.infoFor(title);
        if (info != null) _md[id] = info;
      }
    } catch (_) {}
    if (mounted) setState(() { _future = _loadLocal(); });
  }

  Future<void> _refresh() async => _sync();

  void _open(String mangaId) => context.push('/manga/${Uri.encodeComponent(mangaId)}');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: FutureBuilder<_ProfileData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }
          final data = snap.data;
          if (data == null) {
            return const EmptyView(message: 'Could not load profile.', icon: Icons.person_off);
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              children: [
                _header(context, data),
                _stats(context, data),
                ..._statsCharts(context, data),
                const Divider(),
                _sectionTitle(context, 'Library', data.favorites.length),
                _favorites(data),
                const Divider(),
                _sectionTitle(context, 'History', data.history.length),
                ..._historyTiles(context, data),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, _ProfileData data) {
    final scheme = Theme.of(context).colorScheme;
    final name = data.username ?? 'Account';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: scheme.primaryContainer,
            child: Text(initial,
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: scheme.onPrimaryContainer)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleLarge),
                Text('Signed in',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Log out?'),
                  content: const Text('You will need to sign in again.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
                  ],
                ),
              );
              if (confirm == true) {
                await ref.read(authControllerProvider.notifier).logout();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _stats(BuildContext context, _ProfileData data) {
    final read = data.history.fold<int>(0, (sum, i) => sum + (i.summary?.readCount ?? 0));
    final totalSecs = data.timeByDay.values.fold<int>(0, (s, v) => s + v);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              _stat(context, '${data.favorites.length}', 'In library'),
              _stat(context, '${data.history.length}', 'In history'),
              _stat(context, '$read', 'Chapters read'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat(context, _fmtDuration(totalSecs), 'Reading time'),
              _stat(context, '${_streak(data)}', 'Day streak'),
              _stat(context, '${_chaptersThisWeek(data)}', 'This week'),
            ],
          ),
        ],
      ),
    );
  }

  /// "Xh Ym" / "Ym" total reading time.
  String _fmtDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  /// Days with any reading activity (progress updates or tracked time).
  Set<DateTime> _activeDays(_ProfileData data) {
    final days = <DateTime>{};
    for (final p in data.progressRows) {
      final t = p.updatedAt;
      days.add(DateTime(t.year, t.month, t.day));
    }
    for (final k in data.timeByDay.keys) {
      final t = DateTime.tryParse(k);
      if (t != null) days.add(DateTime(t.year, t.month, t.day));
    }
    for (final h in data.history) {
      final t = h.lastReadAt;
      if (t != null) days.add(DateTime(t.year, t.month, t.day));
    }
    return days;
  }

  /// Consecutive reading days ending today (or yesterday, so an unfinished
  /// today doesn't zero the streak).
  int _streak(_ProfileData data) {
    final days = _activeDays(data);
    final now = DateTime.now();
    var d = DateTime(now.year, now.month, now.day);
    if (!days.contains(d)) {
      d = d.subtract(const Duration(days: 1));
      if (!days.contains(d)) return 0;
    }
    var n = 0;
    while (days.contains(d)) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// Chapters marked read in the current week (since Monday).
  int _chaptersThisWeek(_ProfileData data) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return data.progressRows
        .where((p) => p.read && !p.updatedAt.isBefore(monday))
        .length;
  }

  /// Chapters read per week for the last 8 weeks (oldest first).
  List<int> _weeklyCounts(_ProfileData data) {
    final now = DateTime.now();
    final thisMonday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final counts = List<int>.filled(8, 0);
    for (final p in data.progressRows) {
      if (!p.read) continue;
      final t = p.updatedAt;
      final monday =
          DateTime(t.year, t.month, t.day).subtract(Duration(days: t.weekday - 1));
      final weeksAgo = thisMonday.difference(monday).inDays ~/ 7;
      if (weeksAgo >= 0 && weeksAgo < 8) counts[7 - weeksAgo]++;
    }
    return counts;
  }

  /// Bar chart card: chapters read per week, last 8 weeks. Pure widgets, no
  /// chart dependency.
  Widget _weeklyCard(BuildContext context, _ProfileData data) {
    final scheme = Theme.of(context).colorScheme;
    final counts = _weeklyCounts(data);
    final maxV = counts.fold<int>(0, max);
    if (maxV == 0) return const SizedBox.shrink();
    return _statCard(
      context,
      'Chapters per week',
      SizedBox(
        height: 120,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < counts.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (counts[i] > 0)
                      Text('${counts[i]}',
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Container(
                      height: counts[i] == 0 ? 3 : 64.0 * counts[i] / maxV + 4,
                      decoration: BoxDecoration(
                        color: i == counts.length - 1
                            ? scheme.primary
                            : scheme.primary.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(i == counts.length - 1 ? 'now' : '-${counts.length - 1 - i}w',
                        style: TextStyle(
                            fontSize: 10, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          Text(label,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }

  // Distinct chart colors (app charts can use more than the strict palette).
  static const _chartColors = <Color>[
    Color(0xFFFF8FB1), // pink
    Color(0xFFC4A7E7), // lavender
    Color(0xFF9FD8CB), // teal
    Color(0xFFE6C36B), // gold
    Color(0xFF7FB3FF), // blue
    Color(0xFFB6E07F), // green
  ];

  /// Donut cards built from canonical MangaDex info (only titles MangaDex
  /// matched are counted). Empty until the background fetch fills [_md].
  List<Widget> _statsCharts(BuildContext context, _ProfileData data) {
    final ids = {
      ...data.history.map((e) => e.mangaId),
      ...data.favorites.map((e) => e.mangaId),
    };
    final infos = [for (final id in ids) if (_md[id] != null) _md[id]!];
    final genres = _topGenres(infos);
    final types = _types(infos);
    final cards = <Widget>[];
    cards.add(_weeklyCard(context, data));
    if (types.isNotEmpty) cards.add(_typeCard(context, types));
    if (genres.isNotEmpty) cards.add(_genreCard(context, genres));
    return cards;
  }

  Widget _statCard(BuildContext context, String title, Widget child) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  /// Content type as one full-width stacked proportion bar + inline legend.
  Widget _typeCard(BuildContext context, List<_Seg> segs) {
    final total = segs.fold<double>(0, (s, e) => s + e.value);
    return _statCard(
      context,
      'Content type',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 18,
              child: Row(
                children: [
                  for (final s in segs)
                    Expanded(
                      flex: (s.value * 100).round().clamp(1, 100000),
                      child: ColoredBox(color: s.color),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              for (final s in segs)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 7),
                    Text('${s.label} · ${total > 0 ? (s.value / total * 100).round() : 0}%',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Genres as a ranked "taste meter": horizontal bars sized to the top genre.
  Widget _genreCard(BuildContext context, List<_Seg> segs) {
    final scheme = Theme.of(context).colorScheme;
    final total = segs.fold<double>(0, (s, e) => s + e.value);
    final maxV = segs.map((e) => e.value).reduce(max);
    return _statCard(
      context,
      'Top genres',
      Column(
        children: [
          for (final s in segs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(s.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: maxV > 0 ? (s.value / maxV) : 0,
                          child: Container(
                            height: 10,
                            decoration: BoxDecoration(
                              color: s.color,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text('${total > 0 ? (s.value / total * 100).round() : 0}%',
                        textAlign: TextAlign.end,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<_Seg> _topGenres(List<MdInfo> infos) {
    final counts = <String, int>{};
    for (final info in infos) {
      for (final g in info.genres) {
        counts[g] = (counts[g] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(6).toList();
    return [
      for (var i = 0; i < top.length; i++)
        _Seg(top[i].key, top[i].value.toDouble(), _chartColors[i % _chartColors.length]),
    ];
  }

  List<_Seg> _types(List<MdInfo> infos) {
    final counts = <String, int>{};
    for (final info in infos) {
      final t = info.contentType; // null = unknown origin → not counted
      if (t != null) counts[t] = (counts[t] ?? 0) + 1;
    }
    const order = ['Manhwa', 'Manga', 'Manhua'];
    final segs = <_Seg>[];
    for (var i = 0; i < order.length; i++) {
      final v = counts[order[i]] ?? 0;
      if (v > 0) segs.add(_Seg(order[i], v.toDouble(), _chartColors[i % _chartColors.length]));
    }
    return segs;
  }

  Widget _sectionTitle(BuildContext context, String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text('$count',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _favorites(_ProfileData data) {
    if (data.favorites.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text('No favorites yet. Add some from a manga page.',
            style: TextStyle(color: Colors.white54)),
      );
    }
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: data.favorites.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final f = data.favorites[i];
          return SizedBox(
            width: 124,
            child: MangaPosterCard(
              coverUrl: f.cached?.coverUrl,
              title: f.cached?.title ?? 'Unknown',
              onTap: () => _open(f.mangaId),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _historyTiles(BuildContext context, _ProfileData data) {
    if (data.history.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('No reading history yet.', style: TextStyle(color: Colors.white54)),
        ),
      ];
    }
    return [
      for (final it in data.history)
        ListTile(
          leading: SizedBox(
            width: 40,
            height: 56,
            child: MangaCover(url: it.cached?.coverUrl),
          ),
          title: Text(it.cached?.title ?? 'Unknown',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(_subtitle(it)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(it.mangaId),
        ),
    ];
  }

  String _subtitle(_Item it) {
    final parts = <String>[];
    final last = it.summary?.lastChapter;
    if (last != null) parts.add('Ch. $last');
    if (it.lastReadAt != null) parts.add(_ago(it.lastReadAt!));
    return parts.join(' · ');
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

class _ProfileData {
  _ProfileData({
    required this.username,
    required this.favorites,
    required this.history,
    this.progressRows = const [],
    this.timeByDay = const {},
  });
  final String? username;
  final List<_Item> favorites;
  final List<_Item> history;

  /// Every local progress row (read flags + updatedAt) for stats.
  final List<LocalProgress> progressRows;

  /// yyyy-MM-dd -> seconds spent reading that day.
  final Map<String, int> timeByDay;
}

class _Item {
  _Item(this.mangaId, this.cached, this.summary, {this.lastReadAt});
  final String mangaId;
  final CachedManga? cached;
  final ProgressSummary? summary;
  final DateTime? lastReadAt;
}

/// One slice of a donut chart.
class _Seg {
  _Seg(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}
