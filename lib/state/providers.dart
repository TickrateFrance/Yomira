import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/dio_client.dart';
import '../core/config.dart';
import '../core/discord_presence.dart';
import '../core/reader_settings.dart';
import '../core/runtime_config.dart';
import '../core/tab_refresh.dart';
import '../data/backend/backend_api.dart';
import '../data/local/reader_prefs_store.dart';
import '../data/backend/token_store.dart';
import '../data/local/isar_db.dart';
import '../data/sources/manga_source.dart';
import '../data/sources/source_registry.dart';
import '../data/sources/suwayomi_source.dart';
import '../repositories/auth_repository.dart';
import '../repositories/download_repository.dart';
import '../repositories/library_repository.dart';
import '../repositories/manga_repository.dart';
import '../repositories/reader_repository.dart';

/// LocalDb is created asynchronously at startup and injected via override.
final localDbProvider = Provider<LocalDb>((ref) {
  throw UnimplementedError('localDbProvider must be overridden in main()');
});

/// ConfigStore is created at startup and injected via override.
final configStoreProvider = Provider<ConfigStore>((ref) {
  throw UnimplementedError('configStoreProvider must be overridden in main()');
});

/// Registry of per-tab refresh callbacks, driven by the desktop "R" shortcut.
final tabRefreshProvider = Provider<TabRefresh>((ref) => TabRefresh());

/// Live runtime config (backend URL). Overridden in main() with the resolved
/// initial URL. Changing it rebuilds the backend Dio + clients automatically.
final configProvider =
    StateNotifierProvider<ConfigController, RuntimeConfig>((ref) {
  throw UnimplementedError('configProvider must be overridden in main()');
});

// ---- low-level clients ----

/// Rebuilds whenever the backend URL changes (watches configProvider).
final _backendDioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(configProvider).backendBaseUrl;
  return DioClient.buildBackend(baseUrl);
});

/// HTTP headers for image requests to the Suwayomi server (User-Agent + Basic
/// Auth when configured). Used by covers, reader pages, and downloads.
final suwayomiImageHeadersProvider = Provider<Map<String, String>>((ref) {
  final auth = ref.watch(configProvider).suwayomiAuthHeader;
  return {
    'User-Agent': AppConfig.userAgent,
    if (auth != null) 'Authorization': auth,
  };
});

/// Plain Dio for downloading raw image bytes (UA + Basic Auth when set).
final _imageDioProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(headers: ref.watch(suwayomiImageHeadersProvider)));
});

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// Discord Rich Presence (desktop). Created once; init() called at startup.
final discordPresenceProvider = Provider<DiscordPresence>(
  (ref) => DiscordPresence(ref.watch(configStoreProvider).discordAppId),
);

// ---- content source + registry (Suwayomi only) ----

final _suwayomiDioProvider = Provider<Dio>((ref) {
  final cfg = ref.watch(configProvider);
  return DioClient.buildSuwayomi(
    ref.watch(configStoreProvider).suwayomiBase,
    authHeader: cfg.suwayomiAuthHeader,
  );
});

final _suwayomiSourceProvider = Provider<MangaSource>(
  (ref) => SuwayomiSource(
    ref.watch(_suwayomiDioProvider),
    ref.watch(configStoreProvider).suwayomiBase,
    // Hide 18+ sources unless the user enabled NSFW in Settings. Read live so
    // toggling applies on the next query.
    showNsfw: () => ref.read(readerSettingsProvider).showNsfw,
  ),
);

/// The app sources everything through Suwayomi. Registry is empty (search
/// returns nothing) until SUWAYOMI_BASE is configured.
final sourceRegistryProvider = Provider<SourceRegistry>((ref) {
  final sources = <MangaSource>[];
  if (ref.watch(configStoreProvider).suwayomiBase.isNotEmpty) {
    sources.add(ref.watch(_suwayomiSourceProvider));
  }
  return SourceRegistry(sources);
});

final backendApiProvider = Provider<BackendApi>(
  (ref) => BackendApi(ref.watch(_backendDioProvider), ref.watch(tokenStoreProvider)),
);

// ---- repositories ----

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(backendApiProvider), ref.watch(tokenStoreProvider)),
);

final mangaRepositoryProvider = Provider<MangaRepository>(
  (ref) => MangaRepository(ref.watch(sourceRegistryProvider), ref.watch(localDbProvider)),
);

final readerRepositoryProvider = Provider<ReaderRepository>(
  (ref) => ReaderRepository(
    ref.watch(sourceRegistryProvider),
    ref.watch(backendApiProvider),
    ref.watch(localDbProvider),
  ),
);

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(ref.watch(backendApiProvider), ref.watch(localDbProvider)),
);

final downloadRepositoryProvider = Provider<DownloadRepository>(
  (ref) => DownloadRepository(
    ref.watch(sourceRegistryProvider),
    ref.watch(localDbProvider),
    ref.watch(_imageDioProvider),
  ),
);

// ---- auth state ----

/// Auth status drives routing (logged in vs not).
enum AuthStatus { unknown, loggedOut, loggedIn }

class AuthController extends StateNotifier<AuthStatus> {
  AuthController(this._repo) : super(AuthStatus.unknown);

  final AuthRepository _repo;

  String? get username => _repo.currentUser?.username;

  Future<void> restore() async {
    final ok = await _repo.tryRestore();
    state = ok ? AuthStatus.loggedIn : AuthStatus.loggedOut;
  }

  Future<void> login(String u, String p) async {
    await _repo.login(u, p);
    state = AuthStatus.loggedIn;
  }

  Future<void> register(String u, String p) async {
    await _repo.register(u, p);
    state = AuthStatus.loggedIn;
  }

  Future<void> logout() async {
    await _repo.logout();
    state = AuthStatus.loggedOut;
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthStatus>((ref) {
  return AuthController(ref.watch(authRepositoryProvider));
});

// ---- reader settings (persisted) ----

/// ReaderPrefsStore is created at startup and injected via override.
final readerPrefsStoreProvider = Provider<ReaderPrefsStore>((ref) {
  throw UnimplementedError('readerPrefsStoreProvider must be overridden in main()');
});

class ReaderSettingsController extends StateNotifier<ReaderSettings> {
  ReaderSettingsController(this._store, ReaderSettings initial) : super(initial);

  final ReaderPrefsStore _store;

  void _set(ReaderSettings next) {
    state = next;
    _store.save(next); // fire-and-forget persistence
  }

  void setMode(ReaderMode m) => _set(state.copyWith(mode: m));
  void setQuality(ReaderQuality q) => _set(state.copyWith(quality: q));
  void setShowNsfw(bool v) => _set(state.copyWith(showNsfw: v));
  void setPageWidth(double w) => _set(state.copyWith(
        pageWidth: w.clamp(ReaderSettings.minWidth, ReaderSettings.maxWidth),
      ));
  void toggleMode() => _set(state.copyWith(
        mode: state.mode == ReaderMode.verticalContinuous
            ? ReaderMode.horizontalPaged
            : ReaderMode.verticalContinuous,
      ));
}

/// Overridden in main() with the store + the settings loaded from disk.
final readerSettingsProvider =
    StateNotifierProvider<ReaderSettingsController, ReaderSettings>((ref) {
  throw UnimplementedError('readerSettingsProvider must be overridden in main()');
});
