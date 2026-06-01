import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/responsive.dart';
import '../state/providers.dart';
import 'widgets/app_logo.dart';

/// Hosts the four main sections as a persistent IndexedStack (via go_router's
/// StatefulShellRoute). Switching tabs is instant and keeps each tab's state —
/// no page transition. Adaptive: NavigationRail on desktop, NavigationBar on phones.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.navigationShell});

  /// The indexed-stack shell from StatefulShellRoute. Holds all four tab
  /// branches alive and exposes the current index + branch switching.
  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    (icon: Icons.bookmark, label: 'Library'),
    (icon: Icons.search, label: 'Search'),
    (icon: Icons.history, label: 'History'),
    (icon: Icons.settings, label: 'Settings'),
  ];

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    _assertBrowsing();
  }

  // Re-assert "Browsing" Discord presence (also catches the case where the
  // startup call lands before Discord is ready).
  void _assertBrowsing() =>
      Future.microtask(() => ref.read(discordPresenceProvider).browsing());

  void _go(int index) {
    // goBranch with initialLocation only when re-tapping the active tab (pops
    // that branch to its root, like native tab bars).
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
    _assertBrowsing();
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.navigationShell.currentIndex;
    final body = widget.navigationShell;

    final Widget scaffold = isWide(context)
        ? Scaffold(
            body: Row(
              children: [
                _SideRail(selectedIndex: index, onSelected: _go),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: SafeArea(left: false, child: body)),
              ],
            ),
          )
        : Scaffold(
            body: SafeArea(child: body),
            bottomNavigationBar: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: _go,
              destinations: [
                for (final d in HomeShell._destinations)
                  NavigationDestination(icon: Icon(d.icon), label: d.label),
              ],
            ),
          );

    // Desktop shortcut: "R" refreshes the active tab. A focused text field
    // (e.g. Search) consumes the key first, so typing "r" is unaffected.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR): () =>
            ref.read(tabRefreshProvider).refresh(index),
      },
      child: Focus(autofocus: true, child: scaffold),
    );
  }
}

/// Left navigation rail with a small app brand header (desktop).
class _SideRail extends StatelessWidget {
  const _SideRail({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerLow,
      child: NavigationRail(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        labelType: NavigationRailLabelType.all,
        backgroundColor: Colors.transparent,
        leading: const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              AppLogo(size: 42, radius: 12),
              SizedBox(height: 6),
              Text('Yomira',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        destinations: [
          for (final d in HomeShell._destinations)
            NavigationRailDestination(
              icon: Icon(d.icon),
              label: Text(d.label),
            ),
        ],
      ),
    );
  }
}
