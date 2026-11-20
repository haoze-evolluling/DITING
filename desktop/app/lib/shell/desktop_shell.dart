library;

import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

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

  static const maxContentWidth = 1320.0;

  final StatefulNavigationShell navigationShell;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  static const _autoExpandWidth = 880.0;

  bool? _expandedOverride;

  bool _expandedFor(BuildContext context) =>
      _expandedOverride ??
      MediaQuery.sizeOf(context).width >= _autoExpandWidth;

  void _toggleSidebar() =>
      setState(() => _expandedOverride = !_expandedFor(context));

  void _select(int index) {
    final shell = widget.navigationShell;
    if (index == shell.currentIndex) {
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
