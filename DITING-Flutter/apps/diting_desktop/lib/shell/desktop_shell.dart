/// The desktop window shell, copied from FlClash's `lib/pages/home.dart`: a navigation sidebar
/// beside the page on a window wide enough for one, the floating dock on a narrow one.
///
/// The branch list, paths and page mapping stay in `apps/diting_desktop/lib/router.dart`; this file only
/// decides how the branches are drawn, and never keeps its own idea of which one is current.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/shell/dock_shell.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  /// Wide windows open the labels, as a desktop app should; the toggle is per session, not a
  /// stored preference, because the window size already says which layout the user wants.
  bool _expanded = true;

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
    if (ViewScope.isMobileOf(context)) {
      return DockShell(navigationShell: widget.navigationShell);
    }
    final l10n = context.l10n;
    final destinations = [
      for (final location in branchOrder)
        SidebarDestination(
          glyph: destinationOfBranch(location).glyph,
          label: destinationOfBranch(location).label(l10n),
        ),
    ];
    return Scaffold(
      backgroundColor: SurfaceLevel.page.colorOf(context.colorScheme),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavigationSidebar(
            destinations: destinations,
            selectedIndex: widget.navigationShell.currentIndex,
            expanded: _expanded,
            onSelected: _select,
            onToggle: () => setState(() => _expanded = !_expanded),
          ),
          // No dock floats over the page here, so pages reserve only the plain bottom gap.
          Expanded(
            child: DockInsetScope(
              inset: DockInsetScope.pageBottomGap,
              child: widget.navigationShell,
            ),
          ),
        ],
      ),
    );
  }
}
