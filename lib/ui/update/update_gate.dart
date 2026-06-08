import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_update.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/updater.dart';
import '../widgets/app_logo.dart';

/// Wraps the app. Listens to [appUpdate]:
///  - force -> full unskippable blocking screen (replaces everything)
///  - soft  -> dismissible card over the app
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});
  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  bool _softDismissed = false;

  @override
  void initState() {
    super.initState();
    appUpdate.addListener(_onChange);
  }

  @override
  void dispose() {
    appUpdate.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final u = appUpdate.value;
    if (u?.status == UpdateStatus.force) {
      return ForceUpdateScreen(url: u!.url);
    }
    return Stack(
      children: [
        widget.child,
        if (u?.status == UpdateStatus.soft && !_softDismissed)
          _SoftUpdateCard(
            url: u!.url,
            onDismiss: () => setState(() => _softDismissed = true),
          ),
      ],
    );
  }
}

Future<void> _copyUrl(BuildContext context, String url) async {
  if (url.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: url));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Download link copied: $url')),
    );
  }
}

/// Unskippable blocking screen for a forced update.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppTheme.softGradient),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 84, radius: 22),
                  const SizedBox(height: 24),
                  const Text(
                    'Update required',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This version of Yomira is no longer supported. '
                    'Please install the latest version to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.muted),
                  ),
                  const SizedBox(height: 28),
                  _UpdateInstaller(pageUrl: url),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dismissible card shown for a soft (optional) update.
class _SoftUpdateCard extends StatelessWidget {
  const _SoftUpdateCard({required this.url, required this.onDismiss});
  final String url;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black54,
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(28),
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Update available',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                const Text(
                  'A newer version of Yomira is available. You can keep using this '
                  'one, but updating is recommended.',
                  style: TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 22),
                _UpdateInstaller(pageUrl: url),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      onPressed: onDismiss, child: const Text('Later')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Downloads the latest installer and launches it, with a progress bar. Falls
/// back to copying the download link if self-update isn't available or fails.
class _UpdateInstaller extends StatefulWidget {
  const _UpdateInstaller({required this.pageUrl});

  /// Human-facing downloads page, used as the copy-link fallback.
  final String pageUrl;

  @override
  State<_UpdateInstaller> createState() => _UpdateInstallerState();
}

class _UpdateInstallerState extends State<_UpdateInstaller> {
  final _updater = Updater();
  double _progress = 0;
  bool _busy = false;
  bool _launched = false; // Android installer was opened
  String? _error;

  Future<void> _run() async {
    final url = AppConfig.directUpdateUrl;
    // No direct installer for this platform → just give the link.
    if (url == null || !_updater.supported) {
      _copyFallback();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      await _updater.downloadAndInstall(
        url: url,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      // Windows: the app has already exited. Android: the installer is open.
      if (mounted) {
        setState(() {
          _busy = false;
          _launched = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _describeError(e);
        });
      }
    }
  }

  /// Surface the real reason so failures are diagnosable, not generic.
  String _describeError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        return 'Download refused (HTTP $code) - server login failed.';
      }
      if (code == 404) return 'Installer not found on server (404).';
      if (code != null) return 'Download failed (HTTP $code).';
      return 'Download failed: ${e.type.name}.';
    }
    return 'Update failed: $e';
  }

  void _copyFallback() {
    if (widget.pageUrl.isNotEmpty) _copyUrl(context, widget.pageUrl);
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
                value: _progress == 0 ? null : _progress, minHeight: 8),
          ),
          const SizedBox(height: 8),
          Text('Downloading ${(_progress * 100).round()}%',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: _run,
          icon: Icon(_launched ? Icons.open_in_new : Icons.download),
          label: Text(_launched ? 'Open installer again' : 'Download & install'),
        ),
        if (_launched) ...[
          const SizedBox(height: 8),
          const Text('Installer opened - follow the prompt to finish.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted, fontSize: 12)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          TextButton(
              onPressed: _copyFallback, child: const Text('Copy download link')),
        ],
      ],
    );
  }
}
