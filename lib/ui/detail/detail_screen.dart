import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/responsive.dart';
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
    } catch (e) {
      setState(() => _error = describeBackendError(e));
    } finally {
      if (mounted) setState(() => _loadingChapters = false);
    }
  }

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

  Future<void> _downloadChapter(String chapterGlobalId) async {
    final messenger = ScaffoldMessenger.of(context);
    final downloads = ref.read(downloadRepositoryProvider);
    if (await downloads.isDownloaded(chapterGlobalId)) {
      messenger.showSnackBar(const SnackBar(content: Text('Already downloaded')));
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Downloading…')));
    try {
      await downloads.download(
        mangaId: widget.mangaId,
        chapterId: chapterGlobalId,
        dataSaver: ref.read(readerSettingsProvider).quality == ReaderQuality.dataSaver,
      );
      messenger.showSnackBar(const SnackBar(content: Text('Downloaded for offline')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Download failed: ${describeBackendError(e)}')));
    }
  }

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
    return ListTile(
      dense: true,
      title: Text(c.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: c.group != null ? Text(c.group!) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.pages > 0) Text('${c.pages}p'),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Download for offline',
            onPressed: () => _downloadChapter(c.globalId),
          ),
        ],
      ),
      onTap: () => context.push(
        '/reader/${Uri.encodeComponent(widget.mangaId)}/${Uri.encodeComponent(c.globalId)}',
        extra: _chapters,
      ),
    );
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
