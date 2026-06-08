import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/download_manager.dart';
import '../../core/responsive.dart';
import '../../data/local/models/local_models.dart';
import '../../data/sources/manga_source.dart';
import '../../repositories/auth_repository.dart';
import '../../state/providers.dart';
import '../widgets/async_views.dart';
import '../widgets/manga_cover.dart';

/// [mangaId] is a globalId ("mangadex:uuid" / "comick:hid").
class DetailScreen extends ConsumerStatefulWidget {
  const DetailScreen({super.key, required this.mangaId});

  final String mangaId;

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  UManga? _manga;
  double? _mdRating; // MangaDex 0–10 rating (canonical across sources)
  List<String> _languages = const [];
  String? _selectedLang;
  List<UChapter> _chapters = const [];
  bool _loadingHeader = true;
  bool _loadingChapters = false;
  String? _error;
  bool _isFavorite = false;

  /// Per-chapter read/resume state + which chapters are downloaded.
  Map<String, LocalProgress> _progress = {};
  Set<String> _downloaded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loadingHeader = true;
      _error = null;
    });
    try {
      final repo = ref.read(mangaRepositoryProvider);
      final manga = await repo.detail(widget.mangaId);
      final fav = await ref.read(libraryRepositoryProvider).isFavorite(widget.mangaId);
      final langs = manga.languages.isNotEmpty
          ? manga.languages
          : await repo.languages(widget.mangaId);

      setState(() {
        _manga = manga;
        _isFavorite = fav;
        _languages = langs;
        _selectedLang = _pickDefaultLang(langs);
        _loadingHeader = false;
      });
      if (_selectedLang != null) _loadChapters(_selectedLang!);

      // Canonical star rating from MangaDex (works for any source, by title).
      ref.read(mangadexRatingsProvider).ratingFor(manga.title).then((r) {
        if (mounted && r != null) setState(() => _mdRating = r);
      });
    } catch (e) {
      setState(() {
        _error = describeBackendError(e);
        _loadingHeader = false;
      });
    }
  }

  String? _pickDefaultLang(List<String> langs) {
    if (langs.isEmpty) return null;
    for (final pref in ['en', 'fr']) {
      if (langs.contains(pref)) return pref;
    }
    return langs.first;
  }

  Future<void> _loadChapters(String lang) async {
    setState(() {
      _loadingChapters = true;
      _chapters = const [];
    });
    try {
      final feed = await ref.read(mangaRepositoryProvider).feed(widget.mangaId, lang);
      setState(() => _chapters = feed);
      await _refreshChapterState();
    } catch (e) {
      setState(() => _error = describeBackendError(e));
    } finally {
      if (mounted) setState(() => _loadingChapters = false);
    }
  }

  /// Reload read-progress + downloaded sets (after reading, marking, deleting).
  Future<void> _refreshChapterState() async {
    final progress =
        await ref.read(mangaRepositoryProvider).progressByChapter(widget.mangaId);
    final downloaded =
        await ref.read(downloadRepositoryProvider).downloadedIds(widget.mangaId);
    if (!mounted) return;
    setState(() {
      _progress = progress;
      _downloaded = downloaded;
    });
  }

  bool get _dataSaver =>
      ref.read(readerSettingsProvider).quality == ReaderQuality.dataSaver;

  Future<void> _toggleFavorite() async {
    final lib = ref.read(libraryRepositoryProvider);
    setState(() => _isFavorite = !_isFavorite);
    try {
      if (_isFavorite) {
        await lib.addFavorite(widget.mangaId);
      } else {
        await lib.removeFavorite(widget.mangaId);
      }
    } catch (_) {
      if (mounted) setState(() => _isFavorite = !_isFavorite);
    }
  }

  // ---- continue / resume ----

  /// The chapter "Continue" should open: an in-progress chapter if any, else
  /// the first unread, else the first chapter.
  UChapter? _continueTarget() {
    if (_chapters.isEmpty) return null;
    UChapter? inProgress;
    DateTime? best;
    for (final c in _chapters) {
      final p = _progress[c.globalId];
      if (p != null && !p.read && p.lastPage > 0) {
        if (best == null || p.updatedAt.isAfter(best)) {
          best = p.updatedAt;
          inProgress = c;
        }
      }
    }
    if (inProgress != null) return inProgress;
    for (final c in _chapters) {
      final p = _progress[c.globalId];
      if (p == null || !p.read) return c;
    }
    return _chapters.first;
  }

  Future<void> _openReader(UChapter c) async {
    await context.push(
      '/reader/${Uri.encodeComponent(widget.mangaId)}/${Uri.encodeComponent(c.globalId)}',
      extra: _chapters,
    );
    await _refreshChapterState(); // read state may have changed
  }

  // ---- downloads ----

  void _enqueue(List<UChapter> chapters) {
    final pending =
        chapters.where((c) => !_downloaded.contains(c.globalId)).toList();
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Already downloaded')));
      return;
    }
    ref.read(downloadManagerProvider.notifier).enqueue(
          mangaId: widget.mangaId,
          dataSaver: _dataSaver,
          chapters: [
            for (final c in pending) (chapterId: c.globalId, label: c.label)
          ],
        );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Added ${pending.length} chapter(s) to downloads'),
      action: SnackBarAction(
          label: 'View', onPressed: () => context.push('/downloads')),
    ));
  }

  Future<void> _deleteDownload(UChapter c) async {
    await ref.read(downloadRepositoryProvider).delete(c.globalId);
    await _refreshChapterState();
  }

  // ---- mark read ----

  Future<void> _setRead(List<UChapter> chapters, bool read) async {
    await ref.read(readerRepositoryProvider).setChaptersRead(
          mangaId: widget.mangaId,
          read: read,
          chapters: [
            for (final c in chapters)
              (chapterId: c.globalId, number: c.number, language: c.language)
          ],
        );
    await _refreshChapterState();
  }

  /// Download the next [n] chapters starting from where you'd continue reading
  /// (skips ones already on disk inside [_enqueue]).
  void _downloadNext(int n) {
    if (_chapters.isEmpty) return;
    final target = _continueTarget();
    var start =
        target == null ? 0 : _chapters.indexWhere((c) => c.globalId == target.globalId);
    if (start < 0) start = 0;
    final end = math.min(start + n, _chapters.length);
    _enqueue(_chapters.sublist(start, end));
  }

  void _bulkAction(String value) {
    switch (value) {
      case 'dl_all':
        _enqueue(_chapters);
      case 'dl_unread':
        _enqueue(_chapters
            .where((c) => !(_progress[c.globalId]?.read ?? false))
            .toList());
      case 'dl_next_25':
        _downloadNext(25);
      case 'dl_next_50':
        _downloadNext(50);
      case 'read_all':
        _setRead(_chapters, true);
      case 'unread_all':
        _setRead(_chapters, false);
    }
  }

  /// Download button menu (All / next N / unread).
  Widget _downloadMenu() => PopupMenuButton<String>(
        icon: const Icon(Icons.download),
        tooltip: 'Download',
        onSelected: _bulkAction,
        itemBuilder: (_) => [
          PopupMenuItem(
              value: 'dl_all', child: Text('Download all (${_chapters.length})')),
          const PopupMenuItem(value: 'dl_unread', child: Text('Download unread')),
          const PopupMenuItem(value: 'dl_next_25', child: Text('Download next 25')),
          const PopupMenuItem(value: 'dl_next_50', child: Text('Download next 50')),
        ],
      );

  /// Overflow menu for mark-read actions.
  Widget _moreMenu() => PopupMenuButton<String>(
        onSelected: _bulkAction,
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'read_all', child: Text('Mark all as read')),
          PopupMenuItem(value: 'unread_all', child: Text('Mark all as unread')),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (_loadingHeader) {
      return const Scaffold(body: LoadingView());
    }
    if (_manga == null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorView(message: _error ?? 'Failed to load', onRetry: _load),
      );
    }
    final m = _manga!;
    return isWide(context) ? _wideLayout(m) : _narrowLayout(m);
  }

  /// Phone layout: collapsing cover header over a single scroll.
  Widget _narrowLayout(UManga m) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            actions: [
              IconButton(
                icon: Icon(_isFavorite ? Icons.bookmark : Icons.bookmark_border),
                onPressed: _toggleFavorite,
              ),
              if (_chapters.isNotEmpty) ...[_downloadMenu(), _moreMenu()],
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  MangaCover(url: m.coverUrl, fit: BoxFit.cover),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(child: _continueButton()),
          SliverToBoxAdapter(child: _header(m)),
          SliverToBoxAdapter(child: _languageSelector()),
          _chapterList(),
        ],
      ),
    );
  }

  /// Desktop layout: cover + metadata in a left column, chapters on the right.
  Widget _wideLayout(UManga m) {
    return Scaffold(
      appBar: AppBar(
        title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(_isFavorite ? Icons.bookmark : Icons.bookmark_border),
            onPressed: _toggleFavorite,
          ),
          if (_chapters.isNotEmpty) ...[_downloadMenu(), _moreMenu()],
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 380,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: AspectRatio(
                        aspectRatio: 0.7,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: MangaCover(url: m.coverUrl, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _toggleFavorite,
                    icon: Icon(_isFavorite ? Icons.bookmark : Icons.bookmark_border),
                    label: Text(_isFavorite ? 'In library' : 'Add to library'),
                  ),
                  _continueButton(),
                  _header(m),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _languageSelector(),
                const Divider(height: 1),
                Expanded(child: _chapterListView()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Big "Continue / Start reading" action. Hidden until chapters are loaded.
  Widget _continueButton() {
    final target = _continueTarget();
    if (target == null) return const SizedBox.shrink();
    final hasProgress = _progress.values.any((p) => p.read || p.lastPage > 0);
    final label = hasProgress
        ? 'Continue · Ch. ${target.number ?? '?'}'
        : 'Start reading';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: Text(label),
          onPressed: () => _openReader(target),
        ),
      ),
    );
  }

  Widget _header(UManga m) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _chip(Icons.cloud_outlined, m.displayLabel),
              _chip(Icons.info_outline, m.status),
              if (m.year != null) _chip(Icons.calendar_today, '${m.year}'),
              if (m.follows != null) _chip(Icons.people, '${m.follows} follows'),
            ],
          ),
          if ((_mdRating ?? m.rating) != null) ...[
            const SizedBox(height: 10),
            _stars(_mdRating ?? m.rating!),
          ],
          const SizedBox(height: 12),
          if (m.tags.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in m.tags)
                  Chip(label: Text(t), visualDensity: VisualDensity.compact)
              ],
            ),
          const SizedBox(height: 16),
          Text('Synopsis', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(m.description.isEmpty ? 'No description.' : m.description),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }

  /// 5-star row from a 0–10 rating (MangaDex scale), with the numeric value.
  Widget _stars(double rating10) {
    final scheme = Theme.of(context).colorScheme;
    final outOf5 = (rating10 / 2).clamp(0.0, 5.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            outOf5 >= i + 1
                ? Icons.star
                : (outOf5 >= i + 0.5 ? Icons.star_half : Icons.star_border),
            size: 20,
            color: scheme.primary,
          ),
        const SizedBox(width: 8),
        Text('${rating10.toStringAsFixed(2)} / 10',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
      ],
    );
  }

  Widget _languageSelector() {
    if (_languages.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No translated chapters available.'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Text('Language: '),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: _selectedLang,
            items: [
              for (final l in _languages)
                DropdownMenuItem(value: l, child: Text(l.toUpperCase())),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selectedLang = v);
              _loadChapters(v);
            },
          ),
          const Spacer(),
          Text('${_chapters.length} ch.'),
        ],
      ),
    );
  }

  Widget _chapterTile(UChapter c) {
    final scheme = Theme.of(context).colorScheme;
    final p = _progress[c.globalId];
    final isRead = p?.read ?? false;
    final inProgress = p != null && !p.read && p.lastPage > 0;
    final downloaded = _downloaded.contains(c.globalId);

    // Live download task for this chapter, if queued/running.
    final tasks = ref.watch(downloadManagerProvider);
    DownloadTask? task;
    for (final t in tasks) {
      if (t.chapterId == c.globalId &&
          (t.status == DownloadStatus.downloading ||
              t.status == DownloadStatus.queued)) {
        task = t;
        break;
      }
    }

    final (leadIcon, leadColor) = isRead
        ? (Icons.check_circle, scheme.primary)
        : inProgress
            ? (Icons.play_circle_fill, scheme.tertiary)
            : (Icons.radio_button_unchecked, scheme.onSurfaceVariant);

    return ListTile(
      dense: true,
      leading: Icon(leadIcon, color: leadColor, size: 22),
      title: Text(
        c.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isRead ? scheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: inProgress
          ? Text('Resume · page ${p.lastPage + 1}')
          : (c.group != null ? Text(c.group!) : null),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.pages > 0)
            Text('${c.pages}p',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          const SizedBox(width: 6),
          if (task != null)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: task.total > 0 ? task.fraction : null),
            )
          else if (downloaded)
            Icon(Icons.download_done, color: scheme.primary, size: 20),
          PopupMenuButton<String>(
            onSelected: (v) => _tileAction(v, c),
            itemBuilder: (_) => [
              if (downloaded)
                const PopupMenuItem(value: 'del_dl', child: Text('Delete download'))
              else
                const PopupMenuItem(value: 'dl', child: Text('Download')),
              PopupMenuItem(
                  value: 'read',
                  child: Text(isRead ? 'Mark as unread' : 'Mark as read')),
              const PopupMenuItem(
                  value: 'read_prev', child: Text('Mark previous as read')),
            ],
          ),
        ],
      ),
      onTap: () => _openReader(c),
    );
  }

  void _tileAction(String value, UChapter c) {
    switch (value) {
      case 'dl':
        _enqueue([c]);
      case 'del_dl':
        _deleteDownload(c);
      case 'read':
        _setRead([c], !(_progress[c.globalId]?.read ?? false));
      case 'read_prev':
        final upTo = _chapters.where((x) => x.sortKey <= c.sortKey).toList();
        _setRead(upTo, true);
    }
  }

  /// Sliver chapter list (phone layout).
  Widget _chapterList() {
    if (_loadingChapters) {
      return const SliverToBoxAdapter(
        child: Padding(padding: EdgeInsets.all(32), child: LoadingView()),
      );
    }
    if (_chapters.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: EmptyView(message: 'No chapters in this language', icon: Icons.menu_book),
        ),
      );
    }
    return SliverList.separated(
      itemCount: _chapters.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _chapterTile(_chapters[i]),
    );
  }

  /// Box chapter list (desktop right column).
  Widget _chapterListView() {
    if (_loadingChapters) return const LoadingView();
    if (_chapters.isEmpty) {
      return const EmptyView(
          message: 'No chapters in this language', icon: Icons.menu_book);
    }
    return ListView.separated(
      itemCount: _chapters.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _chapterTile(_chapters[i]),
    );
  }
}
