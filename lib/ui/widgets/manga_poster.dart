import 'package:flutter/material.dart';

import 'manga_cover.dart';

/// A poster-style cover card (cover image + title, optional source badge).
/// Used by the desktop grids for Search and Library.
class MangaPosterCard extends StatelessWidget {
  const MangaPosterCard({
    super.key,
    required this.coverUrl,
    required this.title,
    this.sourceLabel,
    this.onTap,
  });

  final String? coverUrl;
  final String title;
  final String? sourceLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MangaCover(url: coverUrl),
                  if (sourceLabel != null)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          sourceLabel!,
                          style: TextStyle(
                              fontSize: 10, color: scheme.onSecondaryContainer),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.2),
          ),
        ],
      ),
    );
  }
}
