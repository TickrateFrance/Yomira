import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_update.dart';
import '../../core/theme.dart';
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
                  FilledButton.icon(
                    onPressed: url.isEmpty ? null : () => _copyUrl(context, url),
                    icon: const Icon(Icons.download),
                    label: const Text('Get the update'),
                  ),
                  if (url.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(url, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                  ],
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: onDismiss, child: const Text('Later')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: url.isEmpty
                          ? null
                          : () {
                              _copyUrl(context, url);
                              onDismiss();
                            },
                      child: const Text('Update'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
