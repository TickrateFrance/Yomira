import 'package:flutter/widgets.dart';

/// Layout breakpoints + helpers for adaptive (phone vs desktop) UI.
class Breakpoints {
  static const double desktop = 840;
}

/// True when the window is wide enough for a desktop layout (side rail, grids).
/// Width-based so it also reacts to window resizing on desktop.
bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoints.desktop;

/// Number of cover columns for a responsive poster grid, given a target tile
/// width. Clamped to a sensible range.
int coverGridColumns(BuildContext context, {double target = 180}) {
  final w = MediaQuery.sizeOf(context).width;
  return (w / target).floor().clamp(2, 10);
}
