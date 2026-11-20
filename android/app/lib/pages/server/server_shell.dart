import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class ServerDockShell extends ConsumerWidget {
  const ServerDockShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glyphs = [AppGlyphs.dashboard, AppGlyphs.puzzle, AppGlyphs.logs];
    final labels = [
      context.l10n.serverTabHome,
      context.l10n.serverTabHub,
      context.l10n.serverTabLogs,
    ];
    return Scaffold(
      extendBody: true,
      body: DockInsetScope(
        inset: NavigationDock.insetOf(context),
        child: navigationShell,
      ),
      bottomNavigationBar: NavigationDock(
        destinations: [
          for (var index = 0; index < glyphs.length; index++)
            NavigationDockDestination(
              glyph: glyphs[index],
              label: labels[index],
            ),
        ],
        selectedIndex: navigationShell.currentIndex,
        onSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
