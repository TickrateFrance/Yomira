import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../../state/updates_controller.dart';
import '../widgets/async_views.dart';
import '../widgets/manga_cover.dart';

/// Lists library titles you've started that have new (unread) chapters.
class UpdatesScreen extends ConsumerStatefulWidget {
  const UpdatesScreen({super.key});

  @override
  ConsumerState<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends ConsumerState<UpdatesScreen> {
  @override
  void initState() {
    super.initState();
    // First open: kick off a scan if we've never run one this session.
    Future.microtask(() {
      final ctrl = ref.read(updatesControllerProvider.notifier);
      if (!ref.read(updatesControllerProvider).loadedOnce) ctrl.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updatesControllerProvider);
    final ctrl = ref.read(updatesControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Updates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Check for new chapters',
            onPressed: state.loading ? null : ctrl.refresh,
          ),
        ],
      ),
      body: _body(context, state, ctrl),
    );
  }

  Widget _body(BuildContext context, UpdatesState state, UpdatesController ctrl) {
    if (state.loading) {
      final value = state.total == 0 ? null : state.done / state.total;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(value: value),
            ),
            const SizedBox(height: 14),
            Text(state.total == 0
                ? 'Checking your library…'
                : 'Checking ${state.done}/${state.total}…'),
          ],
        ),
      );
    }
    if (state.error != null && state.items.isEmpty) {
      return ErrorView(message: state.error!, onRetry: ctrl.refresh);
    }
    if (state.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: ctrl.refresh,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            EmptyView(
              message: 'No new chapters.\nPull down to check again.',
              icon: Icons.done_all,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: ctrl.refresh,
      child: ListView.separated(
        itemCount: state.items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final u = state.items[i];
          final scheme = Theme.of(context).colorScheme;
          return ListTile(
            leading: SizedBox(
              width: 42,
              height: 58,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: MangaCover(url: u.coverUrl, fit: BoxFit.cover),
              ),
            ),
            title: Text(u.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(u.latestChapter != null
                ? 'Latest: Ch. ${u.latestChapter}'
                : 'New chapters available'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '+${u.newCount}',
                style: TextStyle(
                    color: scheme.onPrimary, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            onTap: () =>
                context.push('/manga/${Uri.encodeComponent(u.mangaId)}'),
          );
        },
      ),
    );
  }
}
