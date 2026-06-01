import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../data/sources/manga_source.dart';
import '../../repositories/auth_repository.dart';
import '../../state/providers.dart';
import '../widgets/async_views.dart';
import '../widgets/overlay_poster.dart';

/// Status filter options matching MangaDex.
const _statuses = ['ongoing', 'completed', 'hiatus', 'cancelled'];

/// Common translated-language filters.
const _languages = {'en': 'English', 'fr': 'French', 'es': 'Spanish', 'ja': 'Japanese'};

class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key});

  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab> {
  final _ctrl = TextEditingController();
  final Set<String> _selectedStatus = {};
  String? _selectedLang;

  bool _loading = false;
  String? _error;
  List<UManga> _results = const [];
  bool _showingPopular = false;

  /// Desktop only: selected library (source label) in the side panel.
  /// null = "All sources". Ignored while a global search is active.
  String? _selectedLibrary;

  /// True once the user has run a search/popular at least once (controls the
  /// initial prompt vs. the "no results" message).
  bool _queried = false;

  @override
  void initState() {
    super.initState();
    // Landing suggestions: blended ~10% MangaDex / ~90% Suwayomi.
    _loadPopular();
    // Desktop "R" refresh shortcut (Search = tab index 1).
    ref.read(tabRefreshProvider).register(1, _refreshTab);
  }

  @override
  void dispose() {
    ref.read(tabRefreshProvider).unregister(1);
    _ctrl.dispose();
    super.dispose();
  }

  /// Re-run the current view (suggestions or the active search).
  Future<void> _refreshTab() async {
    _showingPopular ? _loadPopular() : _search();
  }

  /// Languages to require. When the user hasn't picked a specific one, default
  /// to EN + FR so titles with no English/French chapters are excluded entirely
  /// (MangaDex filters this server-side via availableTranslatedLanguage).
  List<String> get _languageFilter =>
      _selectedLang != null ? [_selectedLang!] : const ['en', 'fr'];

  /// Monotonic token so a stale in-flight load doesn't overwrite a newer one.
  int _loadToken = 0;
  int _page = 1;
  bool _loadingMore = false;
  bool _hasMore = true;

  /// Results from fully-loaded prior pages (current page is appended live).
  List<UManga> _committed = const [];

  void _loadPopular() {
    _showingPopular = true;
    _run(reset: true);
  }

  void _search() {
    final title = _ctrl.text.trim();
    if (title.isEmpty && _selectedStatus.isEmpty) {
      _loadPopular();
      return;
    }
    _showingPopular = false;
    _run(reset: true);
  }

  /// Dispatches a paged fetch for the current mode (suggestions vs. search).
  Future<void> _fetch(int page, void Function(List<UManga>) onUpdate) {
    final repo = ref.read(mangaRepositoryProvider);
    if (_showingPopular) {
      return repo.proposalsProgressive(
          languages: _languageFilter, page: page, onUpdate: onUpdate);
    }
    return repo.searchProgressive(
      title: _ctrl.text.trim(),
      status: _selectedStatus.toList(),
      languages: _languageFilter,
      page: page,
      onUpdate: onUpdate,
    );
  }

  /// Unified loader. [reset] loads page 1 (clears); otherwise appends the next
  /// page (infinite scroll). New pages stream in without exceeding rate limits
  /// (MangaDex is throttled to 5 req/s; one page per scroll).
  Future<void> _run({required bool reset}) async {
    if (reset) {
      _loadToken++;
      _page = 1;
      _committed = const [];
      _hasMore = true;
    } else {
      if (_loadingMore || !_hasMore || _loading) return;
    }
    final token = _loadToken;
    final page = reset ? 1 : _page + 1;
    final base = reset ? <UManga>[] : List<UManga>.of(_committed);

    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
        _results = const [];
        _queried = true;
      } else {
        _loadingMore = true;
      }
    });

    List<UManga> pageAccum = const [];
    try {
      await _fetch(page, (list) {
        if (!mounted || token != _loadToken) return;
        pageAccum = list;
        setState(() {
          _results = [...base, ...list];
          if (reset && list.isNotEmpty) _loading = false;
        });
      });
      if (mounted && token == _loadToken) {
        _hasMore = pageAccum.isNotEmpty;
        if (_hasMore) {
          _committed = [...base, ...pageAccum];
          _page = page;
        }
      }
    } catch (e) {
      if (mounted && token == _loadToken) setState(() => _error = describeBackendError(e));
    } finally {
      if (mounted && token == _loadToken) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _open(UManga m) =>
      context.push('/manga/${Uri.encodeComponent(m.globalId)}');

  @override
  Widget build(BuildContext context) {
    // Isolate the redesign to desktop-width windows; phones keep the original
    // single-column search UI untouched.
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth > 600
          ? _desktopLayout(context)
          : _mobileLayout(context),
    );
  }

  Widget _mobileLayout(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _searchBar(),
          _filters(),
          Expanded(
            child: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.axis == Axis.vertical &&
                        n.metrics.pixels >= n.metrics.maxScrollExtent - 900) {
                      _run(reset: false);
                    }
                    return false;
                  },
                  child: _buildBody(),
                ),
                if (_loadingMore && _results.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 10,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHigh,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        controller: _ctrl,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(
          hintText: 'Search across all your sources…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            icon: const Icon(Icons.arrow_forward_rounded),
            onPressed: _search,
          ),
        ),
      ),
    );
  }

  Widget _filters() {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final s in _statuses)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(s),
                selected: _selectedStatus.contains(s),
                onSelected: (v) => setState(() {
                  v ? _selectedStatus.add(s) : _selectedStatus.remove(s);
                  _search();
                }),
              ),
            ),
          const SizedBox(width: 4),
          for (final entry in _languages.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(entry.value),
                selected: _selectedLang == entry.key,
                onSelected: (v) {
                  setState(() => _selectedLang = v ? entry.key : null);
                  _showingPopular ? _loadPopular() : _search();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _showingPopular ? _loadPopular : _search);
    }
    if (_results.isEmpty) {
      return _queried
          ? const EmptyView(message: 'No results. Try another title.', icon: Icons.search_off)
          : const EmptyView(
              message: 'Search a manga or manhwa across all your sources',
              icon: Icons.auto_stories);
    }
    // Browse (landing) → shelves grouped by source. Search → overlay grid.
    return _showingPopular ? _browse() : _resultsGrid();
  }

  /// Search results: responsive grid of overlay cards.
  Widget _resultsGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: coverGridColumns(context, target: isWide(context) ? 175 : 124),
        childAspectRatio: 0.66,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _results.length,
      itemBuilder: (_, i) =>
          OverlayPosterCard(manga: _results[i], onTap: () => _open(_results[i])),
    );
  }

  /// Browse view: a "Trending" row + one horizontal shelf per source.
  Widget _browse() {
    final groups = <String, List<UManga>>{};
    for (final m in _results) {
      (groups[m.displayLabel] ??= []).add(m);
    }
    final trending = _results.take(14).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        if (trending.isNotEmpty) ...[
          _shelfHeader('🔥 Trending'),
          _shelf(trending, cardWidth: 152, height: 232),
        ],
        for (final entry in groups.entries) ...[
          _shelfHeader(entry.key, count: entry.value.length),
          _shelf(entry.value, cardWidth: 124, height: 196),
        ],
      ],
    );
  }

  Widget _shelfHeader(String title, {int? count}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (count != null) ...[
            const SizedBox(width: 8),
            Text('$count',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _shelf(List<UManga> items, {required double cardWidth, required double height}) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => SizedBox(
          width: cardWidth,
          child: OverlayPosterCard(manga: items[i], onTap: () => _open(items[i])),
        ),
      ),
    );
  }

  // ===================== Desktop split-pane layout =====================

  /// Group loaded results by their underlying source label (the "libraries").
  Map<String, List<UManga>> _groupedBySource() {
    final g = <String, List<UManga>>{};
    for (final m in _results) {
      (g[m.displayLabel] ??= []).add(m);
    }
    return g;
  }

  /// Items shown in the main pane. A global search ignores the side selection;
  /// otherwise filter the browse results to the picked library.
  List<UManga> _visibleItems() {
    if (!_showingPopular) return _results; // global search → all sources
    if (_selectedLibrary == null) return _results; // "All sources"
    return _results.where((m) => m.displayLabel == _selectedLibrary).toList();
  }

  Widget _desktopLayout(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _desktopSidebar(context),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: Column(
              children: [
                _desktopTopBar(context),
                _filters(),
                Expanded(child: _desktopContent(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Left panel: library/source directory. Picking one filters the main pane.
  Widget _desktopSidebar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = _groupedBySource();
    final names = groups.keys.toList()..sort();
    return Container(
      width: 268,
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Row(
              children: [
                Icon(Icons.collections_bookmark, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Text('Libraries', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                _libTile(context,
                    label: 'All sources',
                    icon: Icons.apps,
                    value: null,
                    count: _results.length),
                const Divider(height: 1),
                for (final n in names)
                  _libTile(context,
                      label: n,
                      icon: Icons.menu_book,
                      value: n,
                      count: groups[n]!.length),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _libTile(
    BuildContext context, {
    required String label,
    required IconData icon,
    required String? value,
    required int count,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selectedLibrary == value;
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: scheme.primaryContainer,
      selectedColor: scheme.onPrimaryContainer,
      leading: Icon(icon, size: 20),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: count > 0
          ? Text('$count',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12))
          : null,
      onTap: () => setState(() => _selectedLibrary = value),
    );
  }

  /// Persistent header: current view title + a global search field (top-right)
  /// that always queries across every source regardless of the side selection.
  Widget _desktopTopBar(BuildContext context) {
    final searching = !_showingPopular;
    final title = searching
        ? 'Search results'
        : (_selectedLibrary ?? 'Browse all sources');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 380,
            child: TextField(
              controller: _ctrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search all sources…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searching
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear',
                        onPressed: () {
                          _ctrl.clear();
                          _loadPopular();
                        },
                      )
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward_rounded),
                        onPressed: _search,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopContent(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorView(
          message: _error!, onRetry: _showingPopular ? _loadPopular : _search);
    }
    final items = _visibleItems();
    if (items.isEmpty) {
      return _queried
          ? const EmptyView(
              message: 'No results in this library.', icon: Icons.search_off)
          : const EmptyView(
              message: 'Search a manga or manhwa across all your sources',
              icon: Icons.auto_stories);
    }
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.axis == Axis.vertical &&
                n.metrics.pixels >= n.metrics.maxScrollExtent - 900) {
              _run(reset: false);
            }
            return false;
          },
          child: _desktopGrid(items),
        ),
        if (_loadingMore && items.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Column count is derived from the content pane width (not the full window),
  /// so the grid stays correct next to the side panel.
  Widget _desktopGrid(List<UManga> items) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = (c.maxWidth / 185).floor().clamp(2, 8);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 0.64,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) =>
              OverlayPosterCard(manga: items[i], onTap: () => _open(items[i])),
        );
      },
    );
  }
}
