import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/server/server_overview_page.dart';
import 'package:diting_android/pages/server/server_settings_page.dart';
import 'package:diting_android/pages/server/server_upstream_page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Three-tab shell for server mode (upstream `server/ui/navigation/DnsNavigation.kt`); it replaces
/// the whole `AppShell`, so the six-item dock never shows. `IndexedStack` gives upstream
/// keep-alive.
class ServerModeShell extends StatefulWidget {
  ServerModeShell({super.key});

  @override
  State<ServerModeShell> createState() => _ServerModeShellState();
}

class _ServerModeShellState extends State<ServerModeShell> {
  int _index = 0;

  List<NavigationDockDestination> _destinations(AppL10n l10n) => [
    NavigationDockDestination(glyph: AppGlyphs.dashboard, label: l10n.serverNavOverview),
    NavigationDockDestination(glyph: AppGlyphs.dns, label: l10n.serverUpstreamTitle),
    NavigationDockDestination(glyph: AppGlyphs.settings, label: l10n.serverModeSettings),
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
            ServerOverviewPage(
              onOpenUpstreams: () => _select(1),
              onOpenSettings: () => _select(2),
            ),
            const ServerUpstreamPage(),
            const ServerSettingsPage(),
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
