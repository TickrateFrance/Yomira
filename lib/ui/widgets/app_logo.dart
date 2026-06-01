import 'package:flutter/material.dart';

/// The app's brand logo (the bundled launcher icon), rounded.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 44, this.radius = 14});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/icon/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Fallback if the asset is missing.
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(Icons.menu_book,
              size: size * 0.55, color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }
}
