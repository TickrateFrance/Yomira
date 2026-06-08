import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../data/sources/manga_source.dart';
import '../../repositories/auth_repository.dart';
import '../../state/providers.dart';
import '../widgets/async_views.dart';
import '../widgets/manga_cover.dart';
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

  /// Desktop only: the source picker. Empty = query all sources; otherwise only
  /// these source ids are queried (much faster). Applies to popular + search.
  final Set<String> _selectedSourceIds = {};
  List<SourceInfo> _sources = const [];
  bool _sourcesLoading = true;

  /// Desktop sidebar language filter for the source list: 'all' | 'en' | 'fr'.
  String _sidebarLang = 'all';

  /// Browse mode: false = Trending (popular), true = Latest (new releases).
  bool _showLatest = false;

  /// True once the user has run a search/popular at least once (controls the
  /// initial prompt vs. the "no results" message).
  bool _queried = false;

  @override
  void initState() {
    super.initState();
    // Landing suggestions.
    _loadPopular();
    _loadSources();
    // Desktop "R" refresh shortcut (Search = tab index 1).
    ref.read(tabRefreshProvider).register(1, _refreshTab);
  }

  /// Load the underlying source list for the desktop picker.
  Future<void> _loadSources() async {
    try {
      final list =
          await ref.read(mangaRepositoryProvider).listSources(languages: _languageFilter);
      if (mounted) setState(() { _sources = list; _sourcesLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _sourcesLoading = false);
    }
  }

  /// Re-run whatever view is active (after a source selection change).
  void _rerun() => _showingPopular ? _loadPopular() : _search();

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
  /// Empty selection = all sources (mobile never sets it).
  Future<void> _fetch(int page, void Function(List<UManga>) onUpdate) {
    final repo = ref.read(mangaRepositoryProvider);
    final ids = _selectedSourceIds.isEmpty ? null : _selectedSourceIds.toList();
    if (_showingPopular) {
      return _showLatest
          ? repo.latestProgressive(
              languages: _languageFilter, page: page, sourceIds: ids, onUpdate: onUpdate)
          : repo.proposalsProgressive(
              languages: _languageFilter, page: page, sourceIds: ids, onUpdate: onUpdate);
    }
    return repo.searchProgressive(
      title: _ctrl.text.trim(),
      status: _selectedStatus.toList(),
      languages: _languageFilter,
      page: page,
      sourceIds: ids,
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

  /// Spinner + hint shown while a search/browse is in flight. Cloudflare-backed
  /// sources are solved server-side and can take ~20-30s on a cold load, so we
  /// say so instead of leaving a bare spinner (used on phone and desktop).
  Widget _searchLoading() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Searching all your sources...\n'
              'Cloudflare-protected sources can take up to ~30s on first load.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _searchLoading();
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
    // Both browse and search: grouped-by-title cards → source picker on tap.
    return _resultsGrid();
  }

  /// Grouped by title (one card per series, listing how many sources have it).
  /// Responsive grid of overlay cards. Used for browse + search.
  Widget _resultsGrid() {
    final groups = _groupByTitle(_results);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: coverGridColumns(context, target: isWide(context) ? 175 : 124),
        childAspectRatio: 0.66,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: groups.length,
      itemBuilder: (_, i) => _groupCard(groups[i]),
    );
  }

  // ---- title grouping + source picker ----

  /// Merge same-title results from different sources into one entry.
  List<_TitleGroup> _groupByTitle(List<UManga> list) {
    final map = <String, _TitleGroup>{};
    final order = <String>[];
    for (final m in list) {
      final key = m.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      final g = map[key];
      if (g == null) {
        map[key] = _TitleGroup(m.title, [m]);
        order.add(key);
      } else {
        g.members.add(m);
      }
    }
    return [for (final k in order) map[k]!];
  }

  /// Representative for the card: the member with the newest update (so the
  /// "recently updated" badge reflects any source), else the first.
  UManga _rep(_TitleGroup g) {
    UManga best = g.members.first;
    for (final m in g.members) {
      if (m.updatedAt != null &&
          (best.updatedAt == null || m.updatedAt!.isAfter(best.updatedAt!))) {
        best = m;
      }
    }
    return best;
  }

  Widget _groupCard(_TitleGroup g) {
    final rep = _rep(g);
    final n = g.members.length;
    return OverlayPosterCard(
      manga: rep,
      badgeOverride: n > 1 ? '$n sources' : null,
      onTap: () => n == 1 ? _open(rep) : _openSourcePicker(g),
    );
  }

  /// Sheet listing every source that has this title; pick one to read from.
  void _openSourcePicker(_TitleGroup g) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Read "${g.title}" from',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final m in g.members)
                    ListTile(
                      leading: SizedBox(
                          width: 38, height: 52, child: MangaCover(url: m.coverUrl)),
                      title: Text(m.displayLabel),
                      subtitle: m.languages.isNotEmpty
                          ? Text(m.languages.first.toUpperCase())
                          : null,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(ctx);
                        _open(m);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ===================== Desktop split-pane layout =====================

  // Results already reflect the selected sources (we query only those).
  List<UManga> _visibleItems() => _results;

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

  /// Left panel: multi-select source picker. Checking sources restricts the
  /// query to just them (faster); none checked = all sources.
  Widget _desktopSidebar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 280,
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Row(
              children: [
                Icon(Icons.tune, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Text('Sources', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          // Language filter for which sources are listed.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'en', label: Text('EN')),
                ButtonSegment(value: 'fr', label: Text('FR')),
              ],
              selected: {_sidebarLang},
              onSelectionChanged: (s) => setState(() => _sidebarLang = s.first),
            ),
          ),
          if (_selectedSourceIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: Text('All sources (clear ${_selectedSourceIds.length})'),
                  onPressed: () {
                    setState(_selectedSourceIds.clear);
                    _rerun();
                  },
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _sourcesLoading
                ? const Center(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4)))
                : ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      for (final s in _sources.where((s) =>
                          _sidebarLang == 'all' ||
                          s.lang.toLowerCase() == _sidebarLang ||
                          s.lang.toLowerCase() == 'all'))
                        CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _selectedSourceIds.contains(s.id),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedSourceIds.add(s.id);
                              } else {
                                _selectedSourceIds.remove(s.id);
                              }
                            });
                            _rerun();
                          },
                          title: Text(s.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(s.lang.toUpperCase(),
                              style: const TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Persistent header: current view title + a global search field (top-right).
  Widget _desktopTopBar(BuildContext context) {
    final searching = !_showingPopular;
    final picked = _selectedSourceIds.length;
    final title = searching
        ? 'Search results'
        : (picked == 0
            ? 'Browse all sources'
            : '$picked source${picked == 1 ? '' : 's'} selected');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          // Browsing → Trending/Latest toggle; searching → results title.
          Expanded(
            child: searching
                ? Text(title,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)
                : Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                            value: false,
                            label: Text('Trending'),
                            icon: Icon(Icons.local_fire_department)),
                        ButtonSegment(
                            value: true,
                            label: Text('Latest'),
                            icon: Icon(Icons.fiber_new)),
                      ],
                      selected: {_showLatest},
                      onSelectionChanged: (s) {
                        setState(() => _showLatest = s.first);
                        _loadPopular();
                      },
                    ),
                  ),
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
    if (_loading) return _searchLoading();
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
          // Always grouped-by-title (one card per series → source picker on tap).
          child: _desktopGrid(items, groups: _groupByTitle(items)),
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
  /// so the grid stays correct next to the side panel. Pass [groups] to render
  /// grouped-by-title cards (search); otherwise renders [items] flat (browse).
  Widget _desktopGrid(List<UManga> items, {List<_TitleGroup>? groups}) {
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
          itemCount: groups?.length ?? items.length,
          itemBuilder: groups != null
              ? (_, i) => _groupCard(groups[i])
              : (_, i) => OverlayPosterCard(manga: items[i], onTap: () => _open(items[i])),
        );
      },
    );
  }
}

/// A search result merged across sources (same title, different sources).
class _TitleGroup {
  _TitleGroup(this.title, this.members);
  final String title;
  final List<UManga> members;
}
