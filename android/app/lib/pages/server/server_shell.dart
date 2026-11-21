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
    const icons = [
      TablerIcons.layout_dashboard,
      TablerIcons.puzzle,
      TablerIcons.logs,
    ];
    const filledIcons = [
      TablerIcons.layout_dashboard_filled,
      TablerIcons.puzzle_filled,
      null,
    ];
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
          for (var index = 0; index < icons.length; index++)
            NavigationDockDestination(
              icon: icons[index],
              filledIcon: filledIcons[index],
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
