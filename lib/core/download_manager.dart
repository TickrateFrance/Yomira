import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/download_repository.dart';

enum DownloadStatus { queued, downloading, done, failed }

/// One chapter download in the queue.
class DownloadTask {
  const DownloadTask({
    required this.chapterId,
    required this.mangaId,
    required this.label,
    this.status = DownloadStatus.queued,
    this.done = 0,
    this.total = 0,
  });

  final String chapterId;
  final String mangaId;
  final String label;
  final DownloadStatus status;
  final int done;
  final int total;

  double get fraction => total == 0 ? 0 : (done / total).clamp(0, 1);

  DownloadTask copyWith({DownloadStatus? status, int? done, int? total}) =>
      DownloadTask(
        chapterId: chapterId,
        mangaId: mangaId,
        label: label,
        status: status ?? this.status,
        done: done ?? this.done,
        total: total ?? this.total,
      );
}

/// A description of a chapter to enqueue.
typedef ChapterRef = ({String chapterId, String label});

/// Sequential download queue. Processes one chapter at a time and exposes the
/// live task list so the Downloads screen and chapter rows can show progress.
class DownloadManager extends StateNotifier<List<DownloadTask>> {
  DownloadManager(this._repo) : super(const []);

  final DownloadRepository _repo;
  bool _running = false;

  /// Add chapters to the queue (skips ones already queued/running) and start
  /// processing if idle.
  void enqueue({
    required String mangaId,
    required List<ChapterRef> chapters,
    required bool dataSaver,
  }) {
    final active = {
      for (final t in state)
        if (t.status == DownloadStatus.queued ||
            t.status == DownloadStatus.downloading)
          t.chapterId
    };
    final toAdd = [
      for (final c in chapters)
        if (!active.contains(c.chapterId))
          DownloadTask(
              chapterId: c.chapterId, mangaId: mangaId, label: c.label),
    ];
    if (toAdd.isEmpty) return;
    state = [...state, ...toAdd];
    _pump(dataSaver);
  }

  /// Remove finished/failed tasks from the list.
  void clearFinished() {
    state = [
      for (final t in state)
        if (t.status == DownloadStatus.queued ||
            t.status == DownloadStatus.downloading)
          t
    ];
  }

  /// Drop a not-yet-started task.
  void cancelQueued(String chapterId) {
    state = [
      for (final t in state)
        if (!(t.chapterId == chapterId && t.status == DownloadStatus.queued)) t
    ];
  }

  Future<void> _pump(bool dataSaver) async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final idx = state.indexWhere((t) => t.status == DownloadStatus.queued);
        if (idx < 0) break;
        final task = state[idx];
        _patch(task.chapterId, status: DownloadStatus.downloading);
        try {
          if (!await _repo.isDownloaded(task.chapterId)) {
            await _repo.download(
              mangaId: task.mangaId,
              chapterId: task.chapterId,
              dataSaver: dataSaver,
              onProgress: (d, t) => _patch(task.chapterId, done: d, total: t),
            );
          }
          _patch(task.chapterId, status: DownloadStatus.done);
        } catch (_) {
          _patch(task.chapterId, status: DownloadStatus.failed);
        }
      }
    } finally {
      _running = false;
    }
  }

  void _patch(String chapterId, {DownloadStatus? status, int? done, int? total}) {
    state = [
      for (final t in state)
        if (t.chapterId == chapterId)
          t.copyWith(status: status, done: done, total: total)
        else
          t
    ];
  }
}
