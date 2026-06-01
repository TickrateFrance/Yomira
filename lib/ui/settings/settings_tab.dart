import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart' show AppConfig, ReaderQuality;
import '../../core/reader_settings.dart';
import '../../state/providers.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    final settingsCtrl = ref.read(readerSettingsProvider.notifier);
    final username = ref.read(authControllerProvider.notifier).username;

    return Column(
      children: [
        AppBar(title: const Text('Settings'), automaticallyImplyLeading: false),
        Expanded(
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.person),
                title: Text(username ?? 'Account'),
                subtitle: const Text('Signed in'),
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('Reader', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ListTile(
                title: const Text('Default mode'),
                subtitle: Text(settings.mode == ReaderMode.verticalContinuous
                    ? 'Vertical (webtoon)'
                    : 'Horizontal (manga)'),
                trailing: SegmentedButton<ReaderMode>(
                  segments: const [
                    ButtonSegment(value: ReaderMode.verticalContinuous, icon: Icon(Icons.swap_vert)),
                    ButtonSegment(value: ReaderMode.horizontalPaged, icon: Icon(Icons.swap_horiz)),
                  ],
                  selected: {settings.mode},
                  onSelectionChanged: (s) => settingsCtrl.setMode(s.first),
                ),
              ),
              ListTile(
                title: const Text('Image quality'),
                subtitle: Text(settings.quality == ReaderQuality.data
                    ? 'High (data)'
                    : 'Data saver'),
                trailing: SegmentedButton<ReaderQuality>(
                  segments: const [
                    ButtonSegment(value: ReaderQuality.data, label: Text('High')),
                    ButtonSegment(value: ReaderQuality.dataSaver, label: Text('Saver')),
                  ],
                  selected: {settings.quality},
                  onSelectionChanged: (s) => settingsCtrl.setQuality(s.first),
                ),
              ),
              ListTile(
                title: const Text('Page width'),
                subtitle: Text(
                  settings.pageWidth >= ReaderSettings.maxWidth
                      ? 'Full width'
                      : '${settings.pageWidth.round()} px (margins on wide screens)',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.width_normal, size: 18),
                    Expanded(
                      child: Slider(
                        min: ReaderSettings.minWidth,
                        max: ReaderSettings.maxWidth,
                        divisions: ((ReaderSettings.maxWidth - ReaderSettings.minWidth) / 40).round(),
                        value: settings.pageWidth
                            .clamp(ReaderSettings.minWidth, ReaderSettings.maxWidth),
                        label: settings.pageWidth >= ReaderSettings.maxWidth
                            ? 'Full'
                            : '${settings.pageWidth.round()}',
                        onChanged: (v) => settingsCtrl.setPageWidth(v),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('Content', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.explicit),
                title: const Text('Show NSFW (18+) sources'),
                subtitle: const Text(
                    'Includes sources Suwayomi marks as adult. Off by default.'),
                value: settings.showNsfw,
                onChanged: (v) => settingsCtrl.setShowNsfw(v),
              ),
              const Divider(),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('App version'),
                subtitle: Text('Yomira ${AppConfig.appVersion}'),
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text('Log out'),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Log out?'),
                      content: const Text('You will need to sign in again.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await ref.read(authControllerProvider.notifier).logout();
                  }
                },
              ),
              const Divider(),
              _madeByFooter(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _madeByFooter(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            await Clipboard.setData(const ClipboardData(text: 'https://tickrate.fr'));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied: tickrate.fr')),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Made by Tickrate · Pralexio',
                    style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Text('tickrate.fr',
                    style: TextStyle(color: scheme.primary, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
