import 'package:flutter/material.dart';

import '../../data/sources/manga_source.dart';
import 'manga_cover.dart';

/// Cover card with the title + source badge overlaid on the art (gradient
/// scrim). Used by the browse shelves and the search results grid.
class OverlayPosterCard extends StatelessWidget {
  const OverlayPosterCard({
    super.key,
    required this.manga,
    this.onTap,
    this.badgeOverride,
  });

  final UManga manga;
  final VoidCallback? onTap;

  /// Replaces the source-name badge (e.g. "3 sources" for a grouped result).
  final String? badgeOverride;

  /// "Updated N d/h ago" when the latest chapter is at most a week old.
  String? get _recentLabel {
    final u = manga.updatedAt;
    if (u == null) return null;
    final d = DateTime.now().difference(u);
    if (d.isNegative || d.inDays > 7) return null;
    if (d.inHours < 1) return 'NEW';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recent = _recentLabel;
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
                  badgeOverride ?? manga.displayLabel,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
            // "Recently updated" banner (top-right) — within the last week.
            if (recent != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fiber_new, size: 12, color: scheme.onPrimary),
                      const SizedBox(width: 3),
                      Text(
                        recent,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ],
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
