import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/config.dart' show AppConfig, ReaderQuality;
import '../../core/reader_settings.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';

/// Preset background colors (palette-derived dark tones).
const _bgPresets = <int>[
  0xFF1E1726, // default plum
  0xFF181020,
  0xFF2A2035,
  0xFF0E0E12, // near-black
  0xFF14121A,
  0xFF201430,
];

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    final settingsCtrl = ref.read(readerSettingsProvider.notifier);
    final username = ref.read(authControllerProvider.notifier).username;
    final bg = ref.watch(backgroundProvider);

    return Column(
      children: [
        AppBar(title: const Text('Settings'), automaticallyImplyLeading: false),
        Expanded(
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.person),
                title: Text(username ?? 'Account'),
                subtitle: const Text('View profile, library & history'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile'),
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
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('Appearance', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.palette),
                title: const Text('Background'),
                subtitle: Text(bg.imagePath != null
                    ? 'Custom image'
                    : bg.colorValue != null
                        ? 'Custom color'
                        : 'Default'),
                trailing: bg.isDefault
                    ? null
                    : TextButton(
                        onPressed: () => ref.read(backgroundProvider.notifier).reset(),
                        child: const Text('Reset'),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final c in _bgPresets)
                      _ColorSwatch(
                        color: Color(c),
                        selected: bg.colorValue == c,
                        onTap: () => ref.read(backgroundProvider.notifier).setColor(c),
                      ),
                    // Custom color (RGB sliders).
                    _SwatchButton(
                      icon: Icons.colorize,
                      label: 'Custom',
                      onTap: () => _customColorDialog(context, ref, bg.colorValue ?? 0xFF1E1726),
                    ),
                    // Pick a local image.
                    _SwatchButton(
                      icon: Icons.image,
                      label: 'Image',
                      onTap: () => _pickBackgroundImage(ref),
                    ),
                  ],
                ),
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

  /// Pick an image from the device, copy it into the app's documents dir, and
  /// set it as the background (survives restarts).
  Future<void> _pickBackgroundImage(WidgetRef ref) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final src = res?.files.single.path;
    if (src == null) return;
    final dir = await getApplicationDocumentsDirectory();
    // New filename each time so the OS image cache doesn't show the old one.
    final dest = p.join(dir.path,
        'app_background_${DateTime.now().millisecondsSinceEpoch}${p.extension(src)}');
    await File(src).copy(dest);
    await ref.read(backgroundProvider.notifier).setImage(dest);
  }

  /// Simple RGB color picker (no extra dependency).
  Future<void> _customColorDialog(BuildContext context, WidgetRef ref, int initial) async {
    int r = (initial >> 16) & 0xFF;
    int g = (initial >> 8) & 0xFF;
    int b = initial & 0xFF;
    int pack() => 0xFF000000 | (r << 16) | (g << 8) | b;

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Custom color'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 56,
                decoration: BoxDecoration(
                  color: Color(pack()),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                ),
              ),
              _channel(ctx, 'R', r, (v) => setLocal(() => r = v)),
              _channel(ctx, 'G', g, (v) => setLocal(() => g = v)),
              _channel(ctx, 'B', b, (v) => setLocal(() => b = v)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, pack()), child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (result != null) await ref.read(backgroundProvider.notifier).setColor(result);
  }

  Widget _channel(BuildContext context, String label, int value, ValueChanged<int> onChanged) {
    return Row(
      children: [
        SizedBox(width: 18, child: Text(label)),
        Expanded(
          child: Slider(
            min: 0,
            max: 255,
            value: value.toDouble(),
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(width: 32, child: Text('$value', textAlign: TextAlign.end)),
      ],
    );
  }
}

/// A tappable color square for the background presets.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.pink : Colors.white24,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 20, color: Colors.white)
            : null,
      ),
    );
  }
}

/// A square action button matching the swatch grid (custom color / image).
class _SwatchButton extends StatelessWidget {
  const _SwatchButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, size: 20, semanticLabel: label),
      ),
    );
  }
}
