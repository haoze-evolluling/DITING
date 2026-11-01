import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/app/theme/layout.dart';
import 'package:diting/routes/branches.dart';
import 'package:diting/state/appearance_extra_providers.dart';
import 'package:diting/state/appearance_providers.dart';
import 'package:diting/ui/ui.dart';
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
    final transition = ref.watch(tabTransitionProvider);
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
        child: _TabTransitionHost(
          transition: transition,
          branchIndex: navigationShell.currentIndex,
          child: navigationShell,
        ),
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
    final items = [
      for (final destination in destinations)
        NavigationDockDestination(
          glyph: destination.glyph,
          label: destination.label(context.l10n),
        ),
    ];
    if (_wantsFallbackBar(context, destinations, style)) {
      return _FallbackBar(
        destinations: destinations,
        selectedIndex: selectedIndex,
        onSelected: onSelected,
      );
    }
    // No `SafeArea`: the dock already folds the system bottom inset into its own bottom margin
    // (`NavigationDock._bottomMarginOf`), so wrapping it would pad that inset a second time. The
    // bar would then sit one inset higher while `insetOf` still reserves bar + margin + gap, and
    // the reserved gap would be spent on the padding: content would rest against the glass.
    return NavigationDock(
      destinations: items,
      selectedIndex: selectedIndex,
      onSelected: onSelected,
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

/// Tab switch animation. `indexedStack` only changes the index, so this widget replays the entry
/// itself: one controller outlives the switch, and only its value restarts. Keying the builder by
/// branch index instead would remount the whole shell on every tab switch, re-running each page's
/// first build and dropping scroll positions.
class _TabTransitionHost extends StatefulWidget {
  const _TabTransitionHost({
    required this.transition,
    required this.branchIndex,
    required this.child,
  });

  final TabTransition transition;
  final int branchIndex;
  final Widget child;

  @override
  State<_TabTransitionHost> createState() => _TabTransitionHostState();
}

class _TabTransitionHostState extends State<_TabTransitionHost>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 220);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
    // The first mount has nothing to animate away from.
    value: 1,
  );

  late final Animation<double> _amount = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void didUpdateWidget(_TabTransitionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchIndex != widget.branchIndex &&
        widget.transition != TabTransition.none) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // With animations off, wrap nothing: an `AnimatedBuilder` would still rebuild the subtree.
    if (widget.transition == TabTransition.none) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _amount,
      child: widget.child,
      builder: (context, child) {
        final amount = _amount.value;
        return switch (widget.transition) {
          TabTransition.fade => Opacity(opacity: amount, child: child),
          TabTransition.slide => FractionalTranslation(
            translation: Offset(0.04 * (1 - amount), 0),
            child: Opacity(opacity: amount, child: child),
          ),
          TabTransition.scale => Transform.scale(
            scale: 0.96 + 0.04 * amount,
            child: Opacity(opacity: amount, child: child),
          ),
          TabTransition.none => child!,
        };
      },
    );
  }
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
        for (final destination in destinations)
          NavigationDestination(
            icon: GlyphIcon(destination.glyph),
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
