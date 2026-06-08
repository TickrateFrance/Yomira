import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/download_manager.dart';
import '../../data/local/models/local_models.dart';
import '../../state/providers.dart';
import '../widgets/async_views.dart';
import '../widgets/manga_cover.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  late Future<_Data> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Data> _load() async {
    final repo = ref.read(downloadRepositoryProvider);
    final mangaRepo = ref.read(mangaRepositoryProvider);
    final rows = await repo.all();
    final bytes = await repo.storageBytes();
    final byManga = <String, List<DownloadedChapter>>{};
    for (final r in rows) {
      byManga.putIfAbsent(r.mangaId, () => []).add(r);
    }
    final groups = <_Group>[];
    for (final entry in byManga.entries) {
      final cached = await mangaRepo.cached(entry.key);
      groups.add(_Group(
        mangaId: entry.key,
        title: cached?.title ?? 'Unknown',
        coverUrl: cached?.coverUrl,
        chapterCount: entry.value.length,
        pageCount: entry.value.fold(0, (s, c) => s + c.pageCount),
      ));
    }
    groups.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return _Data(groups: groups, totalBytes: bytes);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _deleteManga(_Group g) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete downloads for "${g.title}"?'),
        content: Text('Frees ${g.chapterCount} chapter(s) from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(downloadRepositoryProvider).deleteForManga(g.mangaId);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(downloadManagerProvider);
    // Reload the on-disk list whenever the number of completed tasks changes.
    ref.listen<List<DownloadTask>>(downloadManagerProvider, (prev, next) {
      final before = prev?.where((t) => t.status == DownloadStatus.done).length ?? 0;
      final after = next.where((t) => t.status == DownloadStatus.done).length;
      if (after != before) _reload();
    });

    final active = tasks
        .where((t) =>
            t.status == DownloadStatus.queued ||
            t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.failed)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          if (tasks.any((t) =>
              t.status == DownloadStatus.done || t.status == DownloadStatus.failed))
            TextButton(
              onPressed: () => ref.read(downloadManagerProvider.notifier).clearFinished(),
              child: const Text('Clear done'),
            ),
        ],
      ),
      body: FutureBuilder<_Data>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }
          final data = snap.data ?? const _Data(groups: [], totalBytes: 0);
          if (active.isEmpty && data.groups.isEmpty) {
            return const EmptyView(
              message: 'No downloads yet.\nDownload chapters from a manga page to read offline.',
              icon: Icons.download_done,
            );
          }
          return ListView(
            children: [
              if (active.isNotEmpty) ...[
                const _SectionHeader('Downloading'),
                for (final t in active) _TaskTile(task: t),
                const Divider(),
              ],
              _StorageHeader(bytes: data.totalBytes, titles: data.groups.length),
              for (final g in data.groups)
                _GroupTile(group: g, onDelete: () => _deleteManga(g)),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      );
}

class _StorageHeader extends StatelessWidget {
  const _StorageHeader({required this.bytes, required this.titles});
  final int bytes;
  final int titles;

  String get _human {
    if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          Icon(Icons.sd_storage, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text('$titles title(s) · $_human on disk',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});
  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (task.status) {
      DownloadStatus.failed => (Icons.error_outline, scheme.error),
      DownloadStatus.downloading => (Icons.downloading, scheme.primary),
      _ => (Icons.schedule, scheme.onSurfaceVariant),
    };
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(task.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: task.status == DownloadStatus.downloading && task.total > 0
          ? LinearProgressIndicator(value: task.fraction)
          : Text(switch (task.status) {
              DownloadStatus.failed => 'Failed',
              DownloadStatus.downloading => 'Starting…',
              _ => 'Queued',
            }),
      trailing: task.status == DownloadStatus.downloading && task.total > 0
          ? Text('${task.done}/${task.total}')
          : null,
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.onDelete});
  final _Group group;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: MangaCover(url: group.coverUrl, fit: BoxFit.cover),
        ),
      ),
      title: Text(group.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${group.chapterCount} chapter(s) · ${group.pageCount} pages'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete downloads',
        onPressed: onDelete,
      ),
      onTap: () =>
          context.push('/manga/${Uri.encodeComponent(group.mangaId)}'),
    );
  }
}

class _Data {
  const _Data({required this.groups, required this.totalBytes});
  final List<_Group> groups;
  final int totalBytes;
}

class _Group {
  _Group({
    required this.mangaId,
    required this.title,
    required this.coverUrl,
    required this.chapterCount,
    required this.pageCount,
  });
  final String mangaId;
  final String title;
  final String? coverUrl;
  final int chapterCount;
  final int pageCount;
}
