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
    _future = _load();
    // Register for the desktop "R" refresh shortcut (History = tab index 2).
    ref.read(tabRefreshProvider).register(2, _refresh);
  }

  @override
  void dispose() {
    ref.read(tabRefreshProvider).unregister(2);
    super.dispose();
  }

  Future<List<_Item>> _load() async {
    await ref.read(libraryRepositoryProvider).pullFromBackend();
    final rows = await ref.read(libraryRepositoryProvider).localHistory(limit: 50);
    final mangaRepo = ref.read(mangaRepositoryProvider);
    final items = <_Item>[];
    for (final h in rows) {
      var cached = await mangaRepo.cached(h.mangaId);
      // Auto-heal: if we have no title/cover for this entry (e.g. read on
      // another device, or never opened on this one), fetch it from the source
      // once and cache it — so it stops showing "Unknown".
      if (cached == null || cached.title.isEmpty) {
        try {
          await mangaRepo.detail(h.mangaId);
          cached = await mangaRepo.cached(h.mangaId);
        } catch (_) {
          // source unreachable — leave as Unknown, try again next load
        }
      }
      final summary = await mangaRepo.progressSummary(h.mangaId);
      items.add(_Item(h, cached, summary));
    }
    return items;
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

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
                          Text(_progressLabel(it.summary)),
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
                      onLongPress: () => _toggle(id),
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

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  String _progressLabel(ProgressSummary s) {
    final parts = <String>[];
    if (s.lastChapter != null) parts.add('Last read: Ch. ${s.lastChapter}');
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
