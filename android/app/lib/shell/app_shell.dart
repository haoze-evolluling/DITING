import 'package:diting_android/pages/server/server_mode_shell.dart';
import 'package:diting_shared/shell/dock_shell.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Android shell for the six dock pages: [DockShell] plus the one Android-only fork, server mode,
/// which swaps the whole tree for [ServerModeShell]. `StatefulShellRoute.indexedStack` gives every
/// branch its own `Navigator` that survives tab switches, so `KeepScope` must not be nested here.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(workModeProvider) == AppWorkMode.server) {
      return ServerModeShell();
    }
    return DockShell(navigationShell: navigationShell);
  }
}
