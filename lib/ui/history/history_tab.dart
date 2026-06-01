import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/local/models/local_models.dart';
import '../../data/sources/manga_source.dart';
import '../../data/sources/source_registry.dart';
import '../../repositories/manga_repository.dart';
import '../../state/providers.dart';
import '../widgets/async_views.dart';
import '../widgets/manga_cover.dart';

class HistoryTab extends ConsumerStatefulWidget {
  const HistoryTab({super.key});

  @override
  ConsumerState<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<HistoryTab> {
  late Future<List<_Item>> _future;

  /// Selected manga globalIds when in multi-select mode.
  final Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _future = _loadLocal(); // instant from cache
    _sync(); // then refresh from backend + heal missing data in the background
    // Register for the desktop "R" refresh shortcut (History = tab index 2).
    ref.read(tabRefreshProvider).register(2, _refresh);
  }

  @override
  void dispose() {
    ref.read(tabRefreshProvider).unregister(2);
    super.dispose();
  }

  /// Fast: read everything from the local cache only (no network).
  Future<List<_Item>> _loadLocal() async {
    final lib = ref.read(libraryRepositoryProvider);
    final repo = ref.read(mangaRepositoryProvider);
    final rows = await lib.localHistory(limit: 50);
    final items = <_Item>[];
    for (final h in rows) {
      items.add(_Item(
          h, await repo.cached(h.mangaId), await repo.progressSummary(h.mangaId)));
    }
    return items;
  }

  /// Background: pull from backend, fill missing title/cover/source, then reload.
  Future<void> _sync() async {
    try {
      final lib = ref.read(libraryRepositoryProvider);
      final repo = ref.read(mangaRepositoryProvider);
      await lib.pullFromBackend();
      final rows = await lib.localHistory(limit: 50);
      for (final h in rows) {
        final c = await repo.cached(h.mangaId);
        if (c == null || c.title.isEmpty || c.sourceName == null) {
          try {
            await repo.detail(h.mangaId);
          } catch (_) {}
        }
      }
    } catch (_) {}
    if (mounted) setState(() { _future = _loadLocal(); });
  }

  Future<void> _refresh() async => _sync();

  void _toggle(String mangaId) {
    setState(() {
      if (!_selected.remove(mangaId)) _selected.add(mangaId);
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $count from history?'),
        content: const Text(
            'This removes the selected titles from your reading history. '
            'Your favorites and downloads are not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final lib = ref.read(libraryRepositoryProvider);
    for (final id in _selected) {
      await lib.deleteHistory(id);
    }
    setState(() => _selected.clear());
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _appBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: FutureBuilder<List<_Item>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const LoadingView();
                }
                final items = snap.data ?? const [];
                if (items.isEmpty) {
                  return ListView(children: const [
                    SizedBox(height: 120),
                    EmptyView(message: 'No reading history yet.', icon: Icons.history),
                  ]);
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final it = items[i];
                    final id = it.history.mangaId;
                    final selected = _selected.contains(id);
                    return ListTile(
                      selected: selected,
                      selectedTileColor:
                          Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      leading: _selecting
                          ? Icon(selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked)
                          : SizedBox(
                              width: 44,
                              height: 60,
                              child: MangaCover(url: it.cached?.coverUrl),
                            ),
                      title: Text(it.cached?.title ?? 'Unknown',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_progressLabel(it.summary, it.cached?.sourceName)),
                          Text(_ago(it.history.lastReadAt),
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: _selecting ? null : const Icon(Icons.play_arrow),
                      onTap: () {
                        if (_selecting) {
                          _toggle(id);
                        } else {
                          _continue(id);
                        }
                      },
                      onLongPress: () =>
                          _selecting ? _toggle(id) : _showItemMenu(it),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _appBar() {
    if (_selecting) {
      return AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel selection',
          onPressed: () => setState(() => _selected.clear()),
        ),
        title: Text('${_selected.length} selected'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete selected',
            onPressed: _deleteSelected,
          ),
        ],
      );
    }
    return AppBar(
      title: const Text('History'),
      automaticallyImplyLeading: false,
    );
  }

  /// Resume reading: jump **instantly** into the reader at the last-read
  /// chapter (no feed wait). The reader resumes the saved page and loads the
  /// full chapter list in the background for next/prev. Falls back to the
  /// detail page only when there's no progress at all.
  Future<void> _continue(String mangaId) async {
    final resume = await ref.read(mangaRepositoryProvider).resumeTarget(mangaId);
    if (!mounted) return;

    if (resume == null) {
      await context.push('/manga/${Uri.encodeComponent(mangaId)}');
      if (mounted) _refresh(); // reflect any reading done
      return;
    }

    // Build a minimal chapter from the saved progress so the reader can open
    // immediately and show "Ch. N" without fetching the feed first.
    final (source, rawId) = SourceRegistry.parseGlobalId(resume.chapterId);
    final stub = UChapter(
      source: source,
      id: rawId,
      number: resume.chapterNumber,
      title: '',
      language: resume.language ?? '',
      pages: 0,
      group: null,
    );

    // Await the reader; when it pops, refresh so History shows the chapter you
    // ended on (e.g. you moved from 35 → 36 inside the reader).
    await context.push(
      '/reader/${Uri.encodeComponent(mangaId)}/${Uri.encodeComponent(resume.chapterId)}',
      extra: [stub],
    );
    if (mounted) _refresh();
  }

  /// Long-press menu for a history entry.
  void _showItemMenu(_Item it) {
    final id = it.history.mangaId;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Continue reading'),
              onTap: () {
                Navigator.pop(ctx);
                _continue(id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Read from another source'),
              subtitle: const Text('Resume at the same chapter elsewhere'),
              onTap: () {
                Navigator.pop(ctx);
                _switchSource(it);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove from history'),
              onTap: () async {
                Navigator.pop(ctx);
                await ref.read(libraryRepositoryProvider).deleteHistory(id);
                await _refresh();
              },
            ),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('Select'),
              onTap: () {
                Navigator.pop(ctx);
                _toggle(id);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _norm(String t) =>
      t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  /// Find the same title on other sources and let the user resume there.
  Future<void> _switchSource(_Item it) async {
    final title = it.cached?.title;
    if (title == null || title.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No title to match — open it once first.')));
      }
      return;
    }
    final repo = ref.read(mangaRepositoryProvider);
    final resume = await repo.resumeTarget(it.history.mangaId);
    final (_, curId) = SourceRegistry.parseGlobalId(it.history.mangaId);
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Read "$title" from another source',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            Flexible(
              child: FutureBuilder<List<UManga>>(
                future: repo.search(title: title),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                        height: 120,
                        child: Center(child: CircularProgressIndicator()));
                  }
                  final want = _norm(title);
                  final seen = <String>{};
                  final cands = <UManga>[];
                  for (final m in snap.data ?? const <UManga>[]) {
                    if (_norm(m.title) != want) continue;
                    if (m.id == curId) continue; // skip the source we came from
                    if (seen.add(m.globalId)) cands.add(m);
                  }
                  if (cands.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Text('No other source has this title.'),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final m in cands)
                        ListTile(
                          leading: SizedBox(
                              width: 38, height: 52, child: MangaCover(url: m.coverUrl)),
                          title: Text(m.displayLabel),
                          subtitle: m.languages.isNotEmpty
                              ? Text(m.languages.first.toUpperCase())
                              : null,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.pop(ctx);
                            _openOnSource(m, resume?.chapterNumber, resume?.language);
                          },
                        ),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Open [target] at the chapter nearest to [chapterNumber] (so resume lands
  /// on the same chapter you were reading on the old source).
  Future<void> _openOnSource(
      UManga target, String? chapterNumber, String? language) async {
    final repo = ref.read(mangaRepositoryProvider);
    final lang = (language != null && language.isNotEmpty)
        ? language
        : (target.languages.isNotEmpty ? target.languages.first : 'en');

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    List<UChapter> chapters = const [];
    try {
      chapters = await repo.feed(target.globalId, lang);
    } catch (_) {}
    if (mounted) Navigator.of(context, rootNavigator: true).pop(); // close loader
    if (!mounted) return;

    if (chapters.isEmpty) {
      await context.push('/manga/${Uri.encodeComponent(target.globalId)}');
      if (mounted) _refresh();
      return;
    }

    // Pick the chapter whose number is closest to where we left off.
    final want = double.tryParse(chapterNumber ?? '');
    UChapter match = chapters.last; // default: latest
    if (want != null) {
      var bestDiff = double.infinity;
      for (final c in chapters) {
        final n = double.tryParse(c.number ?? '');
        if (n == null) continue;
        final d = (n - want).abs();
        if (d < bestDiff) {
          bestDiff = d;
          match = c;
        }
      }
    }
    await context.push(
      '/reader/${Uri.encodeComponent(target.globalId)}/${Uri.encodeComponent(match.globalId)}',
      extra: chapters,
    );
    if (mounted) _refresh();
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  String _progressLabel(ProgressSummary s, String? source) {
    final parts = <String>[];
    if (source != null && source.isNotEmpty) parts.add(source);
    if (s.lastChapter != null) parts.add('Ch. ${s.lastChapter}');
    parts.add('${s.readCount} chapter${s.readCount == 1 ? '' : 's'} read');
    return parts.join(' · ');
  }
}

class _Item {
  _Item(this.history, this.cached, this.summary);
  final LocalHistory history;
  final CachedManga? cached;
  final ProgressSummary summary;
}
