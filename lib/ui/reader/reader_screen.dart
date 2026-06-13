import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/config.dart';
import '../../core/reader_settings.dart';
import '../../data/local/reading_time_store.dart';
import '../../data/sources/manga_source.dart';
import '../../repositories/auth_repository.dart';
import '../../state/providers.dart';

/// Chapter reader. Page URLs come from the content source (MangaDex at-home,
/// ComicK, …) via ReaderRepository. Supports vertical-continuous and
/// horizontal-paged modes, tap-to-hide chrome, and prev/next chapter nav.
///
/// [mangaId] and [chapterId] are globalIds ("mangadex:uuid" / "comick:hid").
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.mangaId,
    required this.chapterId,
    this.chapters = const [],
  });

  final String mangaId;
  final String chapterId;

  /// Ordered chapters for this manga/language (for next/prev + numbers).
  final List<UChapter> chapters;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  String? _error;
  int _pageCount = 0;
  int _current = 0;
  bool _showChrome = true;

  List<String> _localPaths = const [];
  bool get _offline => _localPaths.isNotEmpty;

  /// Set on dispose / chapter change to stop background prefetching.
  bool _prefetchCancelled = false;

  /// Last time the list scrolled — used to ignore taps that merely stop a fling.
  DateTime _lastScroll = DateTime.fromMillisecondsSinceEpoch(0);

  /// Accumulated scroll distance since the last bar toggle. We only flip the bar
  /// once the user has moved past [_chromeThreshold] in one direction, so a tiny
  /// scroll-up to re-read a line doesn't make the bar flicker on/off.
  double _scrollAccum = 0;
  static const double _chromeThreshold = 48;

  /// Remembered aspect ratio (width / height) per page. Once a page has loaded
  /// we know its real height, so when it later scrolls back into view we reserve
  /// the exact same slot instead of a fixed placeholder — this is what stops the
  /// content from "teleporting" when you scroll back up.
  final Map<int, double> _pageAspect = {};

  /// Public MangaDex cover for Discord presence, resolved once per manga and
  /// reused across chapter changes so the cover never flips back to the logo.
  String? _rpcCover;

  // Vertical (webtoon) reader uses index-based scrolling so we can reliably
  // resume to a page on a cold open, before image heights are known.
  final ItemScrollController _itemScrollCtrl = ItemScrollController();
  final ScrollOffsetController _offsetCtrl = ScrollOffsetController();
  final ItemPositionsListener _itemPositions = ItemPositionsListener.create();
  // ScrollablePositionedList doesn't bubble ScrollNotifications reliably, so we
  // observe scrolling through its own offset listener instead.
  final ScrollOffsetListener _offsetListener = ScrollOffsetListener.create();
  StreamSubscription<double>? _offsetSub;

  /// Debounce so we don't write progress on every scrolled pixel.
  Timer? _saveTimer;

  late PageController _pageCtrl;

  /// Chapter list for next/prev. Starts as whatever was passed in (may be a
  /// single stub when resuming from History) and gets filled by [_loadFeed].
  late List<UChapter> _chapters;

  /// Current chapter globalId. Mutable so prev/next can switch chapters
  /// in-place (reloading this screen) instead of navigating to a new route.
  late String _chapterId;

  bool get _dataSaver =>
      ref.read(readerSettingsProvider).quality == ReaderQuality.dataSaver;

  UChapter? get _currentChapter =>
      _chapters.firstWhereOrNull((c) => c.globalId == _chapterId);

  int get _chapterIndex =>
      _chapters.indexWhere((c) => c.globalId == _chapterId);

  UChapter? get _prevChapter {
    final i = _chapterIndex;
    return (i > 0) ? _chapters[i - 1] : null;
  }

  UChapter? get _nextChapter {
    final i = _chapterIndex;
    return (i >= 0 && i < _chapters.length - 1) ? _chapters[i + 1] : null;
  }

  @override
  void initState() {
    super.initState();
    _chapterId = widget.chapterId;
    _chapters = List.of(widget.chapters);
    _pageCtrl = PageController();
    // Hide the system bars for the WHOLE reading session and leave them hidden.
    // The custom top bar is a Stack overlay, so toggling it never resizes the
    // viewport. Setting this once (instead of on every bar toggle) is what stops
    // the image from jumping when the bar shows/hides.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Reading-time stats: clock runs while the reader is open and foregrounded.
    WidgetsBinding.instance.addObserver(this);
    _readClock.start();
    _itemPositions.itemPositions.addListener(_onPositionsChanged);
    _offsetSub = _offsetListener.changes.listen(_onScrollDelta);
    _init();
    // If we only have a stub (resumed from History) or the current chapter
    // isn't in the passed list, fetch the full list so next/prev work.
    if (_chapters.length <= 1 || _chapterIndex < 0) _loadFeed();
  }

  /// Vertical reader only: derive the current page from which items are on
  /// screen and persist it (debounced) so we can resume here next time.
  void _onPositionsChanged() {
    if (ref.read(readerSettingsProvider).mode != ReaderMode.verticalContinuous) {
      return;
    }
    final positions = _itemPositions.itemPositions.value;
    if (positions.isEmpty || _pageCount == 0) return;

    // Top-most item still visible (its trailing edge is below the viewport top).
    final visible = positions.where((p) => p.itemTrailingEdge > 0);
    if (visible.isEmpty) return;
    final topIndex = visible
        .reduce((a, b) => a.itemLeadingEdge <= b.itemLeadingEdge ? a : b)
        .index;

    // The footer sits at index == _pageCount; reaching it means "finished".
    final reachedEnd = positions.any((p) => p.index >= _pageCount);
    final page = topIndex.clamp(0, (_pageCount - 1).clamp(0, 1 << 30));
    if (page != _current) setState(() => _current = page);

    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      _saveProgress(reachedEnd ? _pageCount - 1 : page, read: reachedEnd);
    });
  }

  /// Background-loads the manga's chapter list (for next/prev navigation).
  /// For Suwayomi the language doesn't affect which chapters are returned, so
  /// we fetch regardless of whether a language was stored.
  Future<void> _loadFeed() async {
    try {
      final lang = _currentChapter?.language ?? '';
      final feed = await ref.read(mangaRepositoryProvider).feed(widget.mangaId, lang);
      if (!mounted || feed.isEmpty) return;
      setState(() => _chapters = feed);
    } catch (_) {
      // keep the stub — chapter still readable, just no prev/next yet
    }
  }

  /// Accumulates time spent reading (paused while the app is backgrounded).
  final Stopwatch _readClock = Stopwatch();

  /// Persist the accumulated reading time to the per-day store and reset.
  void _flushReadingTime() {
    final secs = _readClock.elapsed.inSeconds;
    _readClock.reset();
    if (secs > 0) ReadingTimeStore().add(DateTime.now(), secs);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _flushReadingTime();
      _readClock.stop();
    } else if (state == AppLifecycleState.resumed) {
      _readClock.start();
    }
  }

  @override
  void dispose() {
    _flushReadingTime();
    WidgetsBinding.instance.removeObserver(this);
    _prefetchCancelled = true;
    // Back to idle presence when leaving the reader.
    ref.read(discordPresenceProvider).browsing();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _itemPositions.itemPositions.removeListener(_onPositionsChanged);
    _offsetSub?.cancel();
    _saveTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final downloads = ref.read(downloadRepositoryProvider);
      final downloaded = await downloads.get(_chapterId);

      if (downloaded != null && downloaded.pagePaths.isNotEmpty) {
        _localPaths = downloaded.pagePaths;
        _pageCount = downloaded.pageCount;
      } else {
        _pageCount =
            await ref.read(readerRepositoryProvider).pageCount(_chapterId, _dataSaver);
      }

      final progress =
          await ref.read(readerRepositoryProvider).progressFor(_chapterId);
      _current = (progress?.lastPage ?? 0).clamp(0, (_pageCount - 1).clamp(0, 1 << 30));

      setState(() => _loading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToResume());

      // Record that this chapter is now the current one (updates History order +
      // stores language/number for resume), preserving any "finished" flag.
      _saveProgress(_current, read: progress?.read ?? false);

      // Discord Rich Presence (desktop) - show what's being read.
      final cached = await ref.read(mangaRepositoryProvider).cached(widget.mangaId);
      final presence = ref.read(discordPresenceProvider);
      final rpcTitle = cached?.title ?? 'a manga';
      // Pass the already-known cover immediately so changing chapter (same manga)
      // never flips the art back to the logo.
      presence.reading(
        title: rpcTitle,
        chapter: _currentChapter?.number,
        coverUrl: _rpcCover,
      );
      // Resolve a PUBLIC MangaDex cover once (best-effort) - Suwayomi covers are
      // auth-gated and Discord's proxy can't load them.
      final t = cached?.title;
      if (_rpcCover == null && t != null && t.isNotEmpty) {
        ref.read(mangadexRatingsProvider).infoFor(t).then((info) {
          if (!mounted || info?.coverUrl == null) return;
          _rpcCover = info!.coverUrl;
          presence.reading(
            title: rpcTitle,
            chapter: _currentChapter?.number,
            coverUrl: _rpcCover,
          );
        });
      }

      // Warm the disk cache for the whole chapter in the background so pages
      // appear instantly as you scroll. Skipped for already-downloaded chapters.
      if (!_offline) _prefetchAll();
    } catch (e) {
      setState(() {
        _error = describeBackendError(e);
        _loading = false;
      });
    }
  }

  void _jumpToResume() {
    if (_current <= 0) return;
    final mode = ref.read(readerSettingsProvider).mode;
    if (mode == ReaderMode.horizontalPaged) {
      if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(_current);
    } else {
      // Vertical: jump to the saved page by index (heights need not be known).
      if (_itemScrollCtrl.isAttached) _itemScrollCtrl.jumpTo(index: _current);
    }
  }

  /// Downloads every page of the chapter into the shared disk cache, a few at
  /// a time. Display widgets (CachedNetworkImage) then hit the cache instantly.
  /// Disk-only — does not pin decoded images in memory (safe for long webtoons).
  Future<void> _prefetchAll() async {
    final total = _pageCount;
    if (total == 0) return;
    const concurrency = 5;
    var next = 0;
    final cache = DefaultCacheManager();

    Future<void> worker() async {
      while (!_prefetchCancelled) {
        final i = next++;
        if (i >= total) break;
        try {
          final url = await _urlFor(i);
          await cache.downloadFile(
            url,
            authHeaders: ref.read(suwayomiImageHeadersProvider),
          );
        } catch (_) {
          // 403/expired/network — the page widget will resolve/retry on view.
        }
      }
    }

    await Future.wait(
      List.generate(math.min(concurrency, total), (_) => worker()),
    );
  }

  Future<String> _urlFor(int index, {bool refresh = false}) {
    final repo = ref.read(readerRepositoryProvider);
    return refresh
        ? repo.refreshedPageUrl(_chapterId, index, _dataSaver)
        : repo.pageUrl(_chapterId, index, _dataSaver);
  }

  void _onPageReached(int index) {
    if (index == _current) return;
    setState(() => _current = index);
    _saveProgress(index, read: index >= _pageCount - 1);
  }

  void _saveProgress(int page, {required bool read}) {
    ref.read(readerRepositoryProvider).saveProgress(
          mangaId: widget.mangaId,
          chapterId: _chapterId,
          lastPage: page,
          read: read,
          chapterNumber: _currentChapter?.number,
          language: _currentChapter?.language,
        );
  }

  void _setChrome(bool show) {
    if (show == _showChrome || !mounted) return;
    // Only animate the floating overlay bar. The system-UI mode is set ONCE in
    // initState and never switched here — switching it resizes the viewport and
    // makes every image jump, which is exactly the glitch we want to avoid.
    setState(() => _showChrome = show);
  }

  /// Tap handler: toggle the bar, but ignore taps that occur right after a
  /// scroll (those are usually just stopping a fling, not a deliberate tap).
  void _onTapToggle() {
    if (DateTime.now().difference(_lastScroll) < const Duration(milliseconds: 350)) {
      return;
    }
    _setChrome(!_showChrome);
  }

  /// Drive the bar from scroll direction (vertical reader): hide while reading
  /// forward (scroll down), reveal when scrolling back up. Fed by the list's
  /// ScrollOffsetListener. [delta] > 0 = scrolling down, < 0 = scrolling up.
  void _onScrollDelta(double delta) {
    if (!mounted ||
        ref.read(readerSettingsProvider).mode != ReaderMode.verticalContinuous) {
      return;
    }
    _lastScroll = DateTime.now();
    // Reset the tally when the user changes direction so the threshold is
    // measured fresh each way (not from leftover momentum the other way).
    if (delta.sign != _scrollAccum.sign) _scrollAccum = 0;
    _scrollAccum += delta;
    if (_scrollAccum > _chromeThreshold) {
      _setChrome(false); // moved down enough → reading → hide
      _scrollAccum = 0;
    } else if (_scrollAccum < -_chromeThreshold) {
      _setChrome(true); // moved up enough → show controls
      _scrollAccum = 0;
    }
  }

  /// Switch chapter in-place (reload this screen) — avoids go_router route
  /// reuse issues entirely.
  Future<void> _goToChapter(UChapter? c) async {
    if (c == null || c.globalId == _chapterId) return;
    _prefetchCancelled = true; // stop the old chapter's prefetch
    _saveTimer?.cancel();
    if (_itemScrollCtrl.isAttached) _itemScrollCtrl.jumpTo(index: 0);
    if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
    setState(() {
      _chapterId = c.globalId;
      _loading = true;
      _error = null;
      _pageCount = 0;
      _current = 0;
      _localPaths = const [];
      _showChrome = true;
    });
    _prefetchCancelled = false;
    await _init();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      // Keyboard nav for desktop: arrows/space = pages or scroll, [ ] = chapters.
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _onTapToggle,
                // Constrain page width on large screens; the black Scaffold
                // background shows as side bars. No effect when the screen is
                // narrower than pageWidth (phones).
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: settings.pageWidth),
                    child: _buildBody(settings),
                  ),
                ),
              ),
            ),
            _buildTopBar(settings),
          ],
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final mode = ref.read(readerSettingsProvider).mode;

    // Prev/next chapter with [ and ].
    if (key == LogicalKeyboardKey.bracketRight) {
      _goToChapter(_nextChapter);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.bracketLeft) {
      _goToChapter(_prevChapter);
      return KeyEventResult.handled;
    }

    if (mode == ReaderMode.horizontalPaged) {
      if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.pageDown) {
        _pageCtrl.nextPage(
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.pageUp) {
        _pageCtrl.previousPage(
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        return KeyEventResult.handled;
      }
    } else {
      // Vertical (webtoon): left/right arrows change chapter (they're unused for
      // scrolling here). Horizontal keeps them as page turns above.
      if (key == LogicalKeyboardKey.arrowRight) {
        _goToChapter(_nextChapter);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _goToChapter(_prevChapter);
        return KeyEventResult.handled;
      }
      final down = key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.space ||
          key == LogicalKeyboardKey.pageDown;
      final up = key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.pageUp;
      if ((down || up) && _itemScrollCtrl.isAttached) {
        final delta = MediaQuery.sizeOf(context).height * 0.85 * (down ? 1 : -1);
        _offsetCtrl.animateScroll(
            offset: delta,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Widget _buildTopBar(ReaderSettings settings) {
    final title = _currentChapter != null
        ? 'Ch. ${_currentChapter!.number ?? '?'}'
        : 'Reader';
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      top: _showChrome ? 0 : -120,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                    Text('Page ${_current + 1}/$_pageCount',
                        style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
              if (_offline)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.offline_pin, color: Colors.white70, size: 20),
                ),
              IconButton(
                tooltip: 'Previous chapter',
                icon: Icon(Icons.skip_previous,
                    color: _prevChapter == null ? Colors.white24 : Colors.white),
                onPressed: _prevChapter == null ? null : () => _goToChapter(_prevChapter),
              ),
              IconButton(
                tooltip: 'Next chapter',
                icon: Icon(Icons.skip_next,
                    color: _nextChapter == null ? Colors.white24 : Colors.white),
                onPressed: _nextChapter == null ? null : () => _goToChapter(_nextChapter),
              ),
              IconButton(
                tooltip: 'Toggle reading mode',
                icon: Icon(
                  settings.mode == ReaderMode.verticalContinuous
                      ? Icons.swap_horiz
                      : Icons.swap_vert,
                  color: Colors.white,
                ),
                onPressed: () => ref.read(readerSettingsProvider.notifier).toggleMode(),
              ),
              IconButton(
                tooltip: 'Reader settings',
                icon: const Icon(Icons.tune, color: Colors.white),
                onPressed: _openReaderSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Live reader settings, adjustable without leaving the reader. Changes apply
  /// instantly (the reader watches readerSettingsProvider and rebuilds).
  void _openReaderSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final s = ref.watch(readerSettingsProvider);
          final ctrl = ref.read(readerSettingsProvider.notifier);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reader settings',
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 16),

                  const Text('Mode'),
                  const SizedBox(height: 6),
                  SegmentedButton<ReaderMode>(
                    segments: const [
                      ButtonSegment(
                          value: ReaderMode.verticalContinuous,
                          icon: Icon(Icons.swap_vert),
                          label: Text('Webtoon')),
                      ButtonSegment(
                          value: ReaderMode.horizontalPaged,
                          icon: Icon(Icons.swap_horiz),
                          label: Text('Paged')),
                    ],
                    selected: {s.mode},
                    onSelectionChanged: (v) => ctrl.setMode(v.first),
                  ),
                  const SizedBox(height: 16),

                  const Text('Image quality'),
                  const SizedBox(height: 6),
                  SegmentedButton<ReaderQuality>(
                    segments: const [
                      ButtonSegment(value: ReaderQuality.data, label: Text('High')),
                      ButtonSegment(value: ReaderQuality.dataSaver, label: Text('Saver')),
                    ],
                    selected: {s.quality},
                    onSelectionChanged: (v) => ctrl.setQuality(v.first),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      const Text('Page width'),
                      const Spacer(),
                      Text(
                        s.pageWidth >= ReaderSettings.maxWidth
                            ? 'Full'
                            : '${s.pageWidth.round()} px',
                        style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  Slider(
                    min: ReaderSettings.minWidth,
                    max: ReaderSettings.maxWidth,
                    divisions:
                        ((ReaderSettings.maxWidth - ReaderSettings.minWidth) / 40).round(),
                    value: s.pageWidth
                        .clamp(ReaderSettings.minWidth, ReaderSettings.maxWidth),
                    label: s.pageWidth >= ReaderSettings.maxWidth
                        ? 'Full'
                        : '${s.pageWidth.round()}',
                    onChanged: ctrl.setPageWidth,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(ReaderSettings settings) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 40),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _init, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_pageCount == 0) {
      return const Center(
        child: Text('No pages', style: TextStyle(color: Colors.white54)),
      );
    }
    return settings.mode == ReaderMode.verticalContinuous
        ? _verticalReader()
        : _horizontalReader();
  }

  Widget _verticalReader() {
    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollCtrl,
      scrollOffsetController: _offsetCtrl,
      itemPositionsListener: _itemPositions,
      scrollOffsetListener: _offsetListener,
      // Resume: open straight on the saved page. If it's out of range the list
      // clamps it; 0 means start at the top (also the safe fallback).
      initialScrollIndex: _current.clamp(0, _pageCount),
      // Build/keep more offscreen pages so scrolling stays ahead of the eye.
      minCacheExtent: 2400,
      itemCount: _pageCount + 1,
      itemBuilder: (_, i) {
        if (i == _pageCount) return _endOfChapterFooter();
        return _PageImage(
          key: ValueKey('v$i'),
          index: i,
          offlinePath: _offline ? _localPaths[i] : null,
          resolveUrl: _urlFor,
          fit: BoxFit.fitWidth,
          headers: ref.watch(suwayomiImageHeadersProvider),
          aspectRatio: _pageAspect[i],
          onAspectRatio: (r) => _pageAspect[i] = r,
        );
      },
    );
  }

  Widget _horizontalReader() {
    return PageView.builder(
      controller: _pageCtrl,
      // Preloads the adjacent page so swipes feel instant.
      allowImplicitScrolling: true,
      itemCount: _pageCount + 1,
      onPageChanged: (i) {
        if (i < _pageCount) _onPageReached(i);
        if (i == _pageCount) _saveProgress(_pageCount - 1, read: true);
      },
      itemBuilder: (_, i) {
        if (i == _pageCount) {
          return Center(child: _endOfChapterFooter());
        }
        return InteractiveViewer(
          maxScale: 4,
          child: Center(
            child: _PageImage(
              key: ValueKey('h$i'),
              index: i,
              offlinePath: _offline ? _localPaths[i] : null,
              resolveUrl: _urlFor,
              fit: BoxFit.contain,
              headers: ref.watch(suwayomiImageHeadersProvider),
            ),
          ),
        );
      },
    );
  }

  Widget _endOfChapterFooter() {
    final next = _nextChapter;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.white54, size: 40),
          const SizedBox(height: 12),
          const Text('End of chapter', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 20),
          if (next != null)
            FilledButton.icon(
              onPressed: () => _goToChapter(next),
              icon: const Icon(Icons.skip_next),
              label: Text('Next: Ch. ${next.number ?? '?'}'),
            )
          else
            const Text('This is the latest chapter.',
                style: TextStyle(color: Colors.white38)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Back to chapters'),
          ),
        ],
      ),
    );
  }
}

/// One reader page. Resolves its URL on demand (online) or reads a local file
/// (offline). Online failures (e.g. expired baseUrl → 403) show a retry that
/// forces a fresh URL.
class _PageImage extends StatefulWidget {
  const _PageImage({
    super.key,
    required this.index,
    required this.resolveUrl,
    required this.fit,
    required this.headers,
    this.offlinePath,
    this.aspectRatio,
    this.onAspectRatio,
  });

  final int index;
  final String? offlinePath;
  final Future<String> Function(int index, {bool refresh}) resolveUrl;
  final BoxFit fit;
  final Map<String, String> headers;

  /// Known aspect ratio (w/h) for this page, if it has been measured before.
  /// When set (and [fit] is fitWidth) the slot reserves the matching height.
  final double? aspectRatio;

  /// Called once with the real aspect ratio after the image first decodes.
  final void Function(double aspectRatio)? onAspectRatio;

  @override
  State<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<_PageImage> {
  late Future<String> _urlFuture;
  bool _aspectReported = false;

  @override
  void initState() {
    super.initState();
    if (widget.offlinePath == null) {
      _urlFuture = widget.resolveUrl(widget.index);
    }
  }

  void _refresh() {
    setState(() {
      _aspectReported = false;
      _urlFuture = widget.resolveUrl(widget.index, refresh: true);
    });
  }

  /// Read the decoded image's real dimensions (from the in-memory cache, so no
  /// extra download) and report the aspect ratio up once.
  void _captureAspect(ImageProvider provider) {
    if (_aspectReported || widget.onAspectRatio == null) return;
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      if (!mounted || _aspectReported) return;
      _aspectReported = true;
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (h > 0) widget.onAspectRatio!(w / h);
    });
    stream.addListener(listener);
  }

  /// Reserve the known height (for vertical/fitWidth) so the page never resizes
  /// when it scrolls back into view.
  Widget _reserve(Widget child) {
    final ar = widget.aspectRatio;
    if (ar != null && ar > 0 && widget.fit == BoxFit.fitWidth) {
      return AspectRatio(aspectRatio: ar, child: child);
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.offlinePath != null) {
      final provider = FileImage(File(widget.offlinePath!));
      _captureAspect(provider);
      return _reserve(Image(
        image: provider,
        fit: widget.fit,
        errorBuilder: (_, __, ___) => _broken(),
      ));
    }
    return _reserve(FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
            height: 320,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return CachedNetworkImage(
          imageUrl: snap.data!,
          fit: widget.fit,
          httpHeaders: widget.headers,
          imageBuilder: (context, imageProvider) {
            _captureAspect(imageProvider);
            return Image(image: imageProvider, fit: widget.fit);
          },
          placeholder: (_, __) => const SizedBox(
            height: 320,
            child: Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (_, __, ___) => _broken(onRetry: _refresh),
        );
      },
    ));
  }

  Widget _broken({VoidCallback? onRetry}) {
    return SizedBox(
      height: 320,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image, color: Colors.white54),
            const SizedBox(height: 8),
            const Text('Page failed to load', style: TextStyle(color: Colors.white54)),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
