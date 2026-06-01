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

  @override
  void initState() {
    super.initState();
    _future = _load();
    // Desktop "R" refresh shortcut (Library = tab index 0).
    ref.read(tabRefreshProvider).register(0, _refresh);
  }

  @override
  void dispose() {
    ref.read(tabRefreshProvider).unregister(0);
    super.dispose();
  }

  Future<List<_Entry>> _load() async {
    // Refresh from backend then read local.
    await ref.read(libraryRepositoryProvider).pullFromBackend();
    final lib = await ref.read(libraryRepositoryProvider).localLibrary();
    final mangaRepo = ref.read(mangaRepositoryProvider);
    final present = lib.where((e) => e.present).toList();
    final entries = <_Entry>[];
    for (final row in present) {
      final cached = await mangaRepo.cached(row.mangaId);
      entries.add(_Entry(row.mangaId, cached));
    }
    return entries;
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppBar(title: const Text('Library'), automaticallyImplyLeading: false),
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
                    return MangaPosterCard(
                      coverUrl: e.cached?.coverUrl,
                      title: e.cached?.title ?? 'Unknown',
                      onTap: () =>
                          context.push('/manga/${Uri.encodeComponent(e.mangaId)}'),
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
