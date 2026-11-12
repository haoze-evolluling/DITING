import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/server/server_feature_hub_page.dart';
import 'package:diting_android/pages/server/server_home_page.dart';
import 'package:diting_android/pages/server/server_logs_page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Tabbed shell for server mode. It replaces the whole `AppShell`, so the six-item dock never
/// shows. The feature center gathers the module entries; the third tab is the server-specific log
/// dashboard, sharing the normal/express card language but limited to DNS-side data.
class ServerModeShell extends StatefulWidget {
  const ServerModeShell({super.key});

  @override
  State<ServerModeShell> createState() => _ServerModeShellState();
}

class _ServerModeShellState extends State<ServerModeShell> {
  int _index = 0;

  List<NavigationDockDestination> _destinations(AppL10n l10n) => [
    NavigationDockDestination(
      glyph: AppGlyphs.dashboard,
      // Same label as the normal/express home tab: this is a dashboard, not just an overview.
      label: l10n.bottomBarHome,
    ),
    NavigationDockDestination(
      glyph: AppGlyphs.puzzle,
      label: l10n.bottomBarFeatureHub,
    ),
    NavigationDockDestination(
      glyph: AppGlyphs.logs,
      label: l10n.bottomBarLogDashboard,
    ),
  ];

  void _select(int index) {
    if (index == _index) {
      return;
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // As in the main shell, the body supplies its own bottom padding via `DockSpacer` and
      // the bar floats above it.
      extendBody: true,
      body: DockInsetScope(
        // Pages pushed over this shell sit above the scope and keep the plain gap.
        inset: NavigationDock.insetOf(context),
        child: IndexedStack(
          index: _index,
          children: [
            const ServerHomePage(),
            const ServerFeatureHubPage(),
            ServerLogsPage(active: _index == 2),
          ],
        ),
      ),
      // No `SafeArea`, for the same reason as the main shell: the dock folds the system bottom
      // inset into its own margin, and padding it here would eat the reserved content gap.
      bottomNavigationBar: NavigationDock(
        destinations: _destinations(context.l10n),
        selectedIndex: _index,
        onSelected: _select,
      ),
    );
  }
}
