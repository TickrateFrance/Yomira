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
    (icon: Icons.auto_awesome, label: 'Discover'),
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

    // Desktop refresh shortcut: F5 or Ctrl+R (bare "R" is avoided so it never
    // swallows typing in the search field).
    void refresh() => ref.read(tabRefreshProvider).refresh(index);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): refresh,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): refresh,
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
        leading: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelected(0), // back to the main page (Library)
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Column(
                children: [
                  AppLogo(size: 42, radius: 12),
                  SizedBox(height: 6),
                  Text('Yomira',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
        destinations: [
          for (final d in HomeShell._destinations)
            NavigationRailDestination(
              icon: Icon(d.icon),
              label: Text(d.label),
            ),
        ],
        // Pinned to the bottom of the rail: open the user profile.
        trailing: Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.push('/profile'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.account_circle),
                      SizedBox(height: 4),
                      Text('Profile', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
