import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';

/// Paints the app-wide background behind everything. Scaffolds are transparent
/// (see AppTheme), so this shows through. Default = the plum theme color, so
/// nothing changes visually until the user customizes it in Settings.
class AppBackground extends ConsumerWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bg = ref.watch(backgroundProvider);

    Widget layer;
    if (bg.imagePath != null && File(bg.imagePath!).existsSync()) {
      layer = Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(bg.imagePath!),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const ColoredBox(color: AppTheme.bg),
          ),
          // Subtle scrim so foreground text/controls stay readable over photos.
          ColoredBox(color: AppTheme.bg.withValues(alpha: 0.40)),
        ],
      );
    } else if (bg.colorValue != null) {
      layer = ColoredBox(color: Color(bg.colorValue!));
    } else {
      layer = const ColoredBox(color: AppTheme.bg);
    }

    return Stack(
      fit: StackFit.expand,
      children: [layer, child],
    );
  }
}
