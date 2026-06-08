import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../data/local/models/local_models.dart';
import '../../state/providers.dart';
import '../widgets/async_views.dart';
import '../widgets/manga_poster.dart';

class LibraryTab extends ConsumerStatefulWidget {
  const LibraryTab({super.key});

  @override
  ConsumerState<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<LibraryTab> {
  late Future<List<_Entry>> _future;

  /// Selected manga globalIds when in multi-select mode.
  final Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _future = _loadLocal(); // instant from cache
    _sync(); // refresh from backend in the background
    // Desktop "R" refresh shortcut (Library = tab index 0).
    ref.read(tabRefreshProvider).register(0, _refresh);
  }

  @override
  void dispose() {
    ref.read(tabRefreshProvider).unregister(0);
    super.dispose();
  }

  /// Fast: local cache only, no network.
  Future<List<_Entry>> _loadLocal() async {
    final lib = await ref.read(libraryRepositoryProvider).localLibrary();
    final mangaRepo = ref.read(mangaRepositoryProvider);
    final entries = <_Entry>[];
    for (final row in lib.where((e) => e.present)) {
      entries.add(_Entry(row.mangaId, await mangaRepo.cached(row.mangaId)));
    }
    return entries;
  }

  Future<void> _sync() async {
    try {
      await ref.read(libraryRepositoryProvider).pullFromBackend();
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
        title: Text('Remove $count from library?'),
        content: const Text(
            'This removes the selected titles from your favorites. '
            'Your reading history is not affected.'),
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
      await lib.removeFavorite(id);
    }
    setState(() => _selected.clear());
    await _refresh();
  }

  PreferredSizeWidget _appBar() {
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
            tooltip: 'Remove selected',
            onPressed: _deleteSelected,
          ),
        ],
      );
    }
    return AppBar(
      title: const Text('Library'),
      automaticallyImplyLeading: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_active_outlined),
          tooltip: 'Updates (new chapters)',
          onPressed: () => context.push('/updates'),
        ),
        IconButton(
          icon: const Icon(Icons.download_for_offline_outlined),
          tooltip: 'Downloads',
          onPressed: () => context.push('/downloads'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _appBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: FutureBuilder<List<_Entry>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const LoadingView();
                }
                final items = snap.data ?? const [];
                if (items.isEmpty) {
                  return ListView(
                    children: const [
                      SizedBox(height: 120),
                      EmptyView(message: 'No favorites yet.\nAdd some from a manga page.', icon: Icons.bookmark_border),
                    ],
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(14),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: coverGridColumns(context),
                    childAspectRatio: 0.58,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final e = items[i];
                    final selected = _selected.contains(e.mangaId);
                    final scheme = Theme.of(context).colorScheme;
                    return GestureDetector(
                      onLongPress: () => _toggle(e.mangaId),
                      child: Stack(
                        children: [
                          MangaPosterCard(
                            coverUrl: e.cached?.coverUrl,
                            title: e.cached?.title ?? 'Unknown',
                            onTap: () => _selecting
                                ? _toggle(e.mangaId)
                                : context.push(
                                    '/manga/${Uri.encodeComponent(e.mangaId)}'),
                          ),
                          if (_selecting)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: selected
                                        ? scheme.primary.withValues(alpha: 0.25)
                                        : Colors.black26,
                                    border: selected
                                        ? Border.all(color: scheme.primary, width: 3)
                                        : null,
                                  ),
                                  alignment: Alignment.topRight,
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    selected
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    color: selected ? scheme.primary : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
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
}

class _Entry {
  _Entry(this.mangaId, this.cached);
  final String mangaId;
  final CachedManga? cached;
}
