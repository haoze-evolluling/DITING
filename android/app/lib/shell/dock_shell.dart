import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/app/theme/layout.dart';
import 'package:diting_android/routes/branches.dart';
import 'package:diting_android/state/appearance_extra_providers.dart';
import 'package:diting_android/state/appearance_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class DockShell extends ConsumerWidget {
  const DockShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinations = ref.watch(bottomBarProvider);
    final style = ref.watch(bottomBarStyleProvider);
    final selected = _selectedIndex(destinations, navigationShell.currentIndex);

    void onSelected(int index) {
      final branch = branchIndexOf(destinationLocation(destinations[index]));
      if (branch == navigationShell.currentIndex) {
        navigationShell.goBranch(branch, initialLocation: true);
        return;
      }
      navigationShell.goBranch(branch);
    }

    final fallback =
        destinations.isEmpty || _wantsFallbackBar(context, destinations, style);
    return Scaffold(
      extendBody: true,
      body: DockInsetScope(
        inset: destinations.isEmpty
            ? DockInsetScope.pageBottomGap
            : fallback
            ? _FallbackBar.insetOf(context)
            : NavigationDock.insetOf(context),
        child: navigationShell,
      ),
      bottomNavigationBar: destinations.isEmpty
          ? null
          : _Dock(
              destinations: destinations,
              selectedIndex: selected,
              onSelected: onSelected,
              style: style,
            ),
    );
  }

  int _selectedIndex(List<BottomBarDestination> destinations, int branchIndex) {
    final location = branchLocationOf(branchIndex);
    final index = destinations.indexWhere(
      (destination) => destinationLocation(destination) == location,
    );
    return index;
  }
}

String destinationLocation(BottomBarDestination destination) =>
    switch (destination) {
      BottomBarDestination.home => Routes.home,
      BottomBarDestination.featureHub => Routes.hub,
      BottomBarDestination.logDashboard => Routes.logs,
      BottomBarDestination.appTraffic => Routes.traffic,
      BottomBarDestination.networkTools => Routes.tools,
      BottomBarDestination.settings => Routes.settings,
    };


class _Dock extends StatelessWidget {
  const _Dock({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.style,
  });

  final List<BottomBarDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final BottomBarStyle style;

  @override
  Widget build(BuildContext context) {
    final fallbackBar = _wantsFallbackBar(context, destinations, style);
    final Widget bar;
    if (fallbackBar) {
      bar = _FallbackBar(
        destinations: destinations,
        selectedIndex: selectedIndex,
        onSelected: onSelected,
      );
    } else {
      bar = NavigationDock(
        destinations: [
          for (final destination in destinations)
            NavigationDockDestination(
              icon: destination.icon,
              filledIcon: destination.filledIcon,
              label: destination.label(context.l10n),
            ),
        ],
        selectedIndex: selectedIndex,
        onSelected: onSelected,
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => SlideTransition(
        position: animation.drive(
          Tween(begin: const Offset(0, 1), end: Offset.zero),
        ),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: KeyedSubtree(key: ValueKey<bool>(fallbackBar), child: bar),
    );
  }
}

bool _wantsFallbackBar(
  BuildContext context,
  List<BottomBarDestination> destinations,
  BottomBarStyle style,
) {
  return style == BottomBarStyle.docked ||
      !ViewScope.isMobileOf(context, listen: false) ||
      destinations.length > maxDockDestinations;
}


class _FallbackBar extends StatelessWidget {
  const _FallbackBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<BottomBarDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static double insetOf(BuildContext context) {
    final height =
        Theme.of(context).navigationBarTheme.height ??
        const NavigationBarThemeData().height ??
        80;
    return height + MediaQuery.paddingOf(context).bottom + dockContentGap;
  }

  @override
  Widget build(BuildContext context) {
    final bar = NavigationBar(
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      onDestinationSelected: onSelected,
      destinations: [
        for (final (index, destination) in destinations.indexed)
          NavigationDestination(
            icon: SelectedIcon(
              icon: destination.icon,
              filledIcon: destination.filledIcon,
              selected: index == selectedIndex,
            ),
            label: destination.label(context.l10n),
          ),
      ],
    );
    if (selectedIndex >= 0) return bar;

    final theme = Theme.of(context);
    final navigationBarTheme = theme.navigationBarTheme;
    final muted = theme.colorScheme.onSurfaceVariant;
    final iconTheme =
        navigationBarTheme.iconTheme?.resolve(const <WidgetState>{}) ??
        const IconThemeData(size: 24);
    final labelStyle =
        navigationBarTheme.labelTextStyle?.resolve(const <WidgetState>{}) ??
        AppTextRole.dockLabel.of(context);
    return NavigationBarTheme(
      data: navigationBarTheme.copyWith(
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStatePropertyAll(iconTheme.copyWith(color: muted)),
        labelTextStyle: WidgetStatePropertyAll(
          labelStyle.copyWith(color: muted),
        ),
      ),
      child: bar,
    );
  }
}
