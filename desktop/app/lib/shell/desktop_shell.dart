/// The desktop window shell, copied from FlClash's `lib/pages/home.dart`: a navigation sidebar
/// beside the page on a window wide enough for one, the floating dock on a narrow one.
///
/// The branch list, paths and page mapping stay in `desktop/app/lib/router.dart`; this file only
/// decides how the branches are drawn, and never keeps its own idea of which one is current. The
/// labels come from [desktopBranchOrder], not Android's bottom-bar provider: the desktop merges six
/// tabs into three, and a dock built from the mobile preference would light up the wrong branch.
library;

import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Glyph and label of one desktop branch. Both layouts read the same table, so the sidebar and the
/// dock can never disagree.
({Glyph glyph, String label}) desktopDestinationOf(
  AppL10n l10n,
  String location,
) => switch (location) {
  Routes.home => (glyph: AppGlyphs.dashboard, label: l10n.bottomBarHome),
  Routes.hub => (glyph: AppGlyphs.puzzle, label: l10n.bottomBarFeatureHub),
  Routes.about => (glyph: AppGlyphs.info, label: l10n.aboutTitle),
  _ => throw StateError('No desktop destination for branch $location'),
};

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.navigationShell});

  /// Widest column of page content, toolbar included. Beyond this the page stops growing and
  /// centers, so a maximized window on a large monitor keeps a readable measure instead of
  /// stretching every card across the screen. The toolbar is inside the same column as the cards,
  /// so the title never drifts away from the board's left edge.
  static const maxContentWidth = 1320.0;

  final StatefulNavigationShell navigationShell;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  /// The window width below which the sidebar starts collapsed: at 800 the labels would take a
  /// quarter of the window and leave the page one narrow column. A reader who toggles it gets what
  /// they asked for until the window crosses the line again.
  static const _autoExpandWidth = 880.0;

  /// Whether the toggle has been used. Null means "follow the window width", which is what a
  /// window that opens at 800 and is later widened expects, without storing anything.
  bool? _expandedOverride;

  bool _expandedFor(BuildContext context) =>
      _expandedOverride ??
      MediaQuery.sizeOf(context).width >= _autoExpandWidth;

  void _toggleSidebar() =>
      setState(() => _expandedOverride = !_expandedFor(context));

  void _select(int index) {
    final shell = widget.navigationShell;
    if (index == shell.currentIndex) {
      // Re-selecting the current branch returns to its root, as the dock does.
      shell.goBranch(index, initialLocation: true);
      return;
    }
    shell.goBranch(index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final destinations = [
      for (final location in desktopBranchOrder)
        desktopDestinationOf(l10n, location),
    ];
    if (ViewScope.isMobileOf(context)) {
      return Scaffold(
        // Content adds its own bottom padding (`DockSpacer`); the dock floats over it.
        extendBody: true,
        body: DockInsetScope(
          inset: NavigationDock.insetOf(context),
          child: widget.navigationShell,
        ),
        bottomNavigationBar: NavigationDock(
          destinations: [
            for (final destination in destinations)
              NavigationDockDestination(
                glyph: destination.glyph,
                label: destination.label,
              ),
          ],
          selectedIndex: widget.navigationShell.currentIndex,
          onSelected: _select,
        ),
      );
    }
    return Scaffold(
      backgroundColor: SurfaceLevel.page.colorOf(context.colorScheme),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavigationSidebar(
            destinations: [
              for (final destination in destinations)
                SidebarDestination(
                  glyph: destination.glyph,
                  label: destination.label,
                ),
            ],
            selectedIndex: widget.navigationShell.currentIndex,
            expanded: _expandedFor(context),
            onSelected: _select,
            onToggle: _toggleSidebar,
          ),
          // No dock floats over the page here, so pages reserve only the plain bottom gap.
          // The density scope covers the whole shell, not just the dashboard: every page's cards
          // must round, pad and size their titles like desktop cards, and a page that forgot its
          // own scope would silently fall back to the phone metrics.
          Expanded(
            child: DockInsetScope(
              inset: DockInsetScope.pageBottomGap,
              child: PageGutterScope(
                gutter: desktopPageGutter,
                child: DashboardDensityScopeHost(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: DesktopShell.maxContentWidth,
                      ),
                      child: widget.navigationShell,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
