import 'package:flutter/material.dart';

import '../../data/sources/manga_source.dart';
import 'manga_cover.dart';

/// Cover card with the title + source badge overlaid on the art (gradient
/// scrim). Used by the browse shelves and the search results grid.
class OverlayPosterCard extends StatelessWidget {
  const OverlayPosterCard({super.key, required this.manga, this.onTap});

  final UManga manga;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MangaCover(url: manga.coverUrl),
            // Bottom scrim for title legibility.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC0E0A14), Color(0xF2070509)],
                ),
              ),
            ),
            // Source badge.
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  manga.displayLabel,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
            // Title.
            Positioned(
              left: 10,
              right: 10,
              bottom: 9,
              child: Text(
                manga.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
