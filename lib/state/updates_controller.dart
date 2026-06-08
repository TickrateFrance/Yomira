import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/manga_repository.dart';

/// State of the library "Updates" check.
class UpdatesState {
  const UpdatesState({
    this.loading = false,
    this.done = 0,
    this.total = 0,
    this.items = const [],
    this.error,
    this.loadedOnce = false,
  });

  final bool loading;
  final int done;
  final int total;
  final List<UpdateItem> items;
  final String? error;
  final bool loadedOnce;

  UpdatesState copyWith({
    bool? loading,
    int? done,
    int? total,
    List<UpdateItem>? items,
    String? error,
    bool? loadedOnce,
  }) =>
      UpdatesState(
        loading: loading ?? this.loading,
        done: done ?? this.done,
        total: total ?? this.total,
        items: items ?? this.items,
        error: error,
        loadedOnce: loadedOnce ?? this.loadedOnce,
      );
}

/// Drives the Updates screen. Caches the last result in memory so reopening is
/// instant; [refresh] re-scans the library.
class UpdatesController extends StateNotifier<UpdatesState> {
  UpdatesController(this._repo) : super(const UpdatesState());

  final MangaRepository _repo;

  Future<void> refresh() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, error: null, done: 0, total: 0);
    try {
      final items = await _repo.libraryUpdates(onProgress: (d, t) {
        if (mounted) state = state.copyWith(done: d, total: t);
      });
      if (!mounted) return;
      state = UpdatesState(items: items, loadedOnce: true);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: '$e', loadedOnce: true);
    }
  }
}
