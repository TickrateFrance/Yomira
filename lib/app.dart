import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/app_update.dart';
import 'core/theme.dart';
import 'data/sources/manga_source.dart';
import 'state/providers.dart';
import 'ui/update/update_gate.dart';
import 'ui/widgets/app_background.dart';
import 'ui/auth/login_screen.dart';
import 'ui/detail/detail_screen.dart';
import 'ui/downloads/downloads_screen.dart';
import 'ui/history/history_tab.dart';
import 'ui/home_shell.dart';
import 'ui/library/library_tab.dart';
import 'ui/profile/profile_screen.dart';
import 'ui/updates/updates_screen.dart';
import 'ui/reader/reader_screen.dart';
import 'ui/recommend/recommend_screen.dart';
import 'ui/search/search_tab.dart';
import 'ui/settings/settings_tab.dart';
import 'ui/splash_screen.dart';

class TAppReaderApp extends ConsumerStatefulWidget {
  const TAppReaderApp({super.key});

  @override
  ConsumerState<TAppReaderApp> createState() => _TAppReaderAppState();
}

class _TAppReaderAppState extends ConsumerState<TAppReaderApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // Restore session on startup.
    Future.microtask(() => ref.read(authControllerProvider.notifier).restore());
    // Start Discord Rich Presence (desktop only; no-op elsewhere).
    Future.microtask(() => ref.read(discordPresenceProvider).init());
    // Check app version on launch (soft/force). Network errors are ignored;
    // a 426 on any later call still escalates via the interceptor.
    Future.microtask(() async {
      try {
        appUpdate.value = await ref.read(backendApiProvider).appStatus();
      } catch (_) {}
    });
    _router = _buildRouter();
  }

  GoRouter _buildRouter() {
    return GoRouter(
      initialLocation: '/splash',
      refreshListenable: _AuthListenable(ref),
      redirect: (context, state) {
        final status = ref.read(authControllerProvider);
        final loc = state.matchedLocation;

        if (status == AuthStatus.unknown) {
          return loc == '/splash' ? null : '/splash';
        }
        final loggedIn = status == AuthStatus.loggedIn;
        final onAuth = loc == '/login';

        if (!loggedIn) return onAuth ? null : '/login';
        if (loggedIn && (onAuth || loc == '/splash')) return '/library';
        return null;
      },
      routes: [
        GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        // Four main tabs as a persistent indexed stack — instant switching,
        // each tab keeps its state, no page transition.
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              HomeShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/library', builder: (_, __) => const LibraryTab()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/search', builder: (_, __) => const SearchTab()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/history', builder: (_, __) => const HistoryTab()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/discover', builder: (_, __) => const RecommendScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/settings', builder: (_, __) => const SettingsTab()),
            ]),
          ],
        ),
        GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        GoRoute(path: '/downloads', builder: (_, __) => const DownloadsScreen()),
        GoRoute(path: '/updates', builder: (_, __) => const UpdatesScreen()),
        GoRoute(
          // :id is a URL-encoded globalId ("mangadex:uuid" / "comick:hid").
          path: '/manga/:id',
          builder: (_, state) =>
              DetailScreen(mangaId: Uri.decodeComponent(state.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/reader/:mangaId/:chapterId',
          builder: (_, state) {
            final chapterId = Uri.decodeComponent(state.pathParameters['chapterId']!);
            return ReaderScreen(
              // Unique key per chapter so prev/next navigation (pushReplacement
              // to the same route) creates a fresh state and reloads the chapter.
              key: ValueKey(chapterId),
              mangaId: Uri.decodeComponent(state.pathParameters['mangaId']!),
              chapterId: chapterId,
              chapters: (state.extra as List<UChapter>?) ?? const [],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Yomira',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      routerConfig: _router,
      builder: (context, child) => AppBackground(
        child: UpdateGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// Bridges the Riverpod auth state into go_router's refresh mechanism.
/// Uses [WidgetRef.listenManual] because this is created outside a build
/// method (during initState), where `ref.listen` is not allowed.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(WidgetRef ref) {
    _sub = ref.listenManual(authControllerProvider, (_, __) => notifyListeners());
  }

  late final ProviderSubscription<AuthStatus> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
