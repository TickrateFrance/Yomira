import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/background_settings.dart';
import 'core/runtime_config.dart';
import 'data/local/background_store.dart';
import 'data/local/isar_db.dart';
import 'data/local/reader_prefs_store.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env (backend URL etc.) before resolving config.
  await ConfigStore.loadEnv();

  // Open the local DB before building the app so providers can read it.
  final localDb = await LocalDb.open();

  // Resolve the effective backend URL + Suwayomi login: override > .env.
  final configStore = ConfigStore();
  final initialBackendUrl = await configStore.resolveInitial();
  final (suwUser, suwPass) = await configStore.resolveSuwayomiCreds();

  // Load persisted reader preferences (mode, quality, page width).
  final readerPrefs = ReaderPrefsStore();
  final initialReaderSettings = await readerPrefs.load();

  // Load persisted background customization (color / image).
  final backgroundStore = BackgroundStore();
  final initialBackground = await backgroundStore.load();

  runApp(
    ProviderScope(
      overrides: [
        localDbProvider.overrideWithValue(localDb),
        configStoreProvider.overrideWithValue(configStore),
        configProvider.overrideWith(
          (ref) => ConfigController(
            configStore,
            RuntimeConfig(
              backendBaseUrl: initialBackendUrl,
              suwayomiUser: suwUser,
              suwayomiPass: suwPass,
            ),
          ),
        ),
        readerPrefsStoreProvider.overrideWithValue(readerPrefs),
        readerSettingsProvider.overrideWith(
          (ref) => ReaderSettingsController(readerPrefs, initialReaderSettings),
        ),
        backgroundStoreProvider.overrideWithValue(backgroundStore),
        backgroundProvider.overrideWith(
          (ref) => BackgroundController(backgroundStore, initialBackground),
        ),
      ],
      child: const TAppReaderApp(),
    ),
  );
}
