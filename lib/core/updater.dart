import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'config.dart';

/// Downloads the latest installer and launches it, so the user can update from
/// inside the app instead of re-downloading from the website.
///
/// - **Windows**: downloads `Yomira-Setup.exe` and runs it silently (Inno Setup
///   flags); the app exits so the installer can replace files and relaunch.
/// - **Android**: downloads `Yomira-latest.apk` and opens the system package
///   installer. The OS still shows its install confirmation (no silent install
///   for a sideloaded app) - that's expected and unavoidable without root.
class Updater {
  Updater([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              followRedirects: true,
              connectTimeout: const Duration(seconds: 30),
              // No sendTimeout: a download is a GET with no body, and dio throws
              // when sendTimeout is set on a request that sends nothing.
              receiveTimeout: const Duration(minutes: 10),
            ));

  final Dio _dio;

  bool get supported => Platform.isAndroid || Platform.isWindows;

  /// Download [url] then install. [onProgress] reports 0..1.
  /// On Windows this does not return (the app exits to let the installer run).
  Future<void> downloadAndInstall({
    required String url,
    void Function(double progress)? onProgress,
  }) async {
    if (!supported) {
      throw UnsupportedError('Self-update is not available on this platform.');
    }

    final fileName =
        Platform.isWindows ? 'Yomira-Setup.exe' : 'Yomira-latest.apk';
    final dir = await _downloadDir();
    final dest = p.join(dir.path, fileName);

    // Drop any stale copy so a half-finished file can't be installed.
    final file = File(dest);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    final auth = AppConfig.updateAuthHeader;
    await _dio.download(
      url,
      dest,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
      // UA so a host/WAF doesn't reject us; Basic-Auth login for the gated folder.
      options: Options(headers: {
        'User-Agent': AppConfig.userAgent,
        if (auth.isNotEmpty) 'Authorization': auth,
      }),
    );

    if (Platform.isWindows) {
      // Silent, close-and-restart the app. Detached so it survives our exit.
      await Process.start(
        dest,
        const [
          '/SILENT',
          '/CLOSEAPPLICATIONS',
          '/RESTARTAPPLICATIONS',
          '/NORESTART',
        ],
        mode: ProcessStartMode.detached,
      );
      // Let the installer spawn, then quit so it can overwrite our files.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      exit(0);
    } else {
      // Android: hand the APK to the system installer.
      final res = await OpenFilex.open(
        dest,
        type: 'application/vnd.android.package-archive',
      );
      if (res.type != ResultType.done) {
        throw Exception(res.message);
      }
    }
  }

  Future<Directory> _downloadDir() async {
    if (Platform.isAndroid) {
      // App-specific external dir (no permission needed, FileProvider-shareable).
      return await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    }
    return getTemporaryDirectory();
  }
}
