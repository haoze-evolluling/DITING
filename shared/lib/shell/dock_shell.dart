import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/app/theme/layout.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/state/appearance_extra_providers.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The tabbed shell shared by both app roots: six `StatefulShellRoute` branches, a floating
/// [NavigationDock] on narrow layouts and a plain [NavigationBar] when the dock would not fit.
///
/// Android and desktop differ only in what surrounds it (server mode, startup gates, data sources),
/// never in how the tabs are drawn, ordered or animated. Keep this the single implementation.
class DockShell extends ConsumerWidget {
  const DockShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinations = ref.watch(bottomBarProvider);
    final haptic = ref.watch(hapticProvider);
    final style = ref.watch(bottomBarStyleProvider);
    final selected = _selectedIndex(destinations, navigationShell.currentIndex);

    void onSelected(int index) {
      // The dock reports a destination index, `goBranch` wants a branch index; the dock is a
      // subset of the six branches, so passing it through would be wrong.
      final branch = branchIndexOf(destinationLocation(destinations[index]));
      if (branch == navigationShell.currentIndex) {
        // Re-tapping the current tab returns to the branch root (upstream).
        navigationShell.goBranch(branch, initialLocation: true);
        return;
      }
      if (haptic) {
        HapticFeedback.selectionClick();
      }
      navigationShell.goBranch(branch);
    }

    final fallback =
        destinations.isEmpty || _wantsFallbackBar(context, destinations, style);
    return Scaffold(
      // Content adds its own bottom padding (`DockSpacer`); the dock floats over it.
      extendBody: true,
      body: DockInsetScope(
        // Pages pushed over this shell sit above the scope and get the plain gap instead.
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

  /// Maps a branch index to a dock index, or -1 when the branch is not in the dock. Never
  /// fall back to 0: the dock would light up "home" and tapping it counts as tapping the
  /// selected item, trapping the user.
  int _selectedIndex(List<BottomBarDestination> destinations, int branchIndex) {
    final location = branchLocationOf(branchIndex);
    final index = destinations.indexWhere(
      (destination) => destinationLocation(destination) == location,
    );
    return index;
  }
}

/// Dock destination to route.
String destinationLocation(BottomBarDestination destination) =>
    switch (destination) {
      BottomBarDestination.home => Routes.home,
      BottomBarDestination.featureHub => Routes.hub,
      BottomBarDestination.logDashboard => Routes.logs,
      BottomBarDestination.appTraffic => Routes.traffic,
      BottomBarDestination.networkTools => Routes.tools,
      BottomBarDestination.settings => Routes.settings,
    };

/// Route to the dock destination that owns it. The sidebar lists every branch, and a branch it
/// cannot name would be a silent hole, so this throws instead of returning null.
BottomBarDestination destinationOfBranch(String location) {
  for (final destination in BottomBarDestination.values) {
    if (destinationLocation(destination) == location) return destination;
  }
  throw StateError('No bottom-bar destination for branch $location');
}

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
      // No `SafeArea`: the dock already folds the system bottom inset into its own bottom margin
      // (`NavigationDock._bottomMarginOf`), so wrapping it would pad that inset a second time. The
      // bar would then sit one inset higher while `insetOf` still reserves bar + margin + gap, and
      // the reserved gap would be spent on the padding: content would rest against the glass.
      bar = NavigationDock(
        destinations: [
          for (final destination in destinations)
            NavigationDockDestination(
              glyph: destination.glyph,
              label: destination.label(context.l10n),
            ),
        ],
        selectedIndex: selectedIndex,
        onSelected: onSelected,
      );
    }
    // Float↔dock swaps animate like FlClash's `AnimatedVisibility`: the leaving bar
    // slides down and fades while the arriving one slides up into place.
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

/// Whether the plain `NavigationBar` replaces the floating dock. It is meant for many items, so it
/// also wins when the style asks for it: the widget and the inset scope must agree on this.
bool _wantsFallbackBar(
  BuildContext context,
  List<BottomBarDestination> destinations,
  BottomBarStyle style,
) {
  return style == BottomBarStyle.docked ||
      !ViewScope.isMobileOf(context, listen: false) ||
      destinations.length > maxDockDestinations;
}

/// Tab switch animation lives in the shell route's `navigatorContainerBuilder`
/// (`BranchTransitionShell`), so the shell body is the branch tree itself.

class _FallbackBar extends StatelessWidget {
  const _FallbackBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<BottomBarDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Room the plain bar takes below content: its own height plus the system bottom inset plus the
  /// clearance the floating dock leaves above itself. `NavigationBar` sits flush against the edge
  /// inside its own `SafeArea`, so it pads the gesture inset itself and the reserve has to include
  /// that inset; otherwise the bar eats the clearance and content rests against it.
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
      // `NavigationBar` requires 0 <= selectedIndex < length, but off-dock branches pass -1.
      // Clamping satisfies the assert; `_unlit` below hides the resulting highlight.
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      onDestinationSelected: onSelected,
      destinations: [
        for (final (index, destination) in destinations.indexed)
          NavigationDestination(
            icon: AnimatedGlyph(
              glyph: destination.glyph,
              filled: index == selectedIndex,
            ),
            label: destination.label(context.l10n),
          ),
      ],
    );
    if (selectedIndex >= 0) return bar;

    // The current branch is not in the dock (e.g. `/settings` with the default three tabs). The
    // dock floats over the page and lights nothing; this bar cannot express "none", so it must not
    // claim the user is on the first tab either. Same bar, every destination painted unselected.
    final theme = Theme.of(context);
    final navigationBarTheme = theme.navigationBarTheme;
    final muted = theme.colorScheme.onSurfaceVariant;
    final iconTheme =
        navigationBarTheme.iconTheme?.resolve(const <WidgetState>{}) ??
        const IconThemeData(size: 24);
    final labelStyle =
        navigationBarTheme.labelTextStyle?.resolve(const <WidgetState>{}) ??
        theme.textTheme.labelMedium;
    return NavigationBarTheme(
      data: navigationBarTheme.copyWith(
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStatePropertyAll(
          iconTheme.copyWith(color: muted),
        ),
        labelTextStyle: WidgetStatePropertyAll(
          labelStyle?.copyWith(color: muted),
        ),
      ),
      child: bar,
    );
  }
}
