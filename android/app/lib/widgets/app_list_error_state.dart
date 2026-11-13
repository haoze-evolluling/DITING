/// The "cannot read the app list" state every picker shares. Its action asks the system for the
/// app-list permission — MIUI/HyperOS, ColorOS and EMUI gate enumeration behind one — and reloads
/// the inventory afterwards, because a bare retry would fail for the same reason.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/permissions_bridge.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_android/state/permission_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/empty_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class AppListErrorState extends ConsumerStatefulWidget {
  const AppListErrorState({
    super.key,
    required this.error,
    this.minHeight = 260,
  });

  /// Why enumeration failed, shown verbatim: the ROM's own wording is the best hint.
  final String error;

  /// Floor height; the description length varies with the platform message.
  final double minHeight;

  @override
  ConsumerState<AppListErrorState> createState() => _AppListErrorStateState();
}

class _AppListErrorStateState extends ConsumerState<AppListErrorState>
    with WidgetsBindingObserver {
  /// Blocks a second tap while the system dialog or the settings screen is up.
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The grant happens outside the page (system dialog, or the settings screen the fallback
    // opens), so re-read the inventory on return instead of leaving a stale error up.
    if (state == AppLifecycleState.resumed) {
      _reload();
    }
  }

  void _reload() {
    ref.read(installedAppsRevisionProvider.notifier).bump();
  }

  Future<void> _requestPermission() async {
    if (_requesting) {
      return;
    }
    setState(() => _requesting = true);
    final notifier = ref.read(permissionStatesProvider.notifier);
    final snapshot = await notifier.request(AppPermission.appList);
    if (!mounted) {
      return;
    }
    setState(() => _requesting = false);
    if (snapshot.of(AppPermission.appList) != true) {
      // No dialog exists on this ROM (or the user denied): only the settings screen can change it.
      await notifier.openSystemSettings(AppPermission.appList);
      if (!mounted) {
        return;
      }
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return EmptyStateBox(
      minHeight: widget.minHeight,
      child: NullStatus(
        label: context.l10n.appListUnavailable,
        description: widget.error,
        illustration: NullStatusIllustration.apps,
        action: TextButton(
          onPressed: _requesting ? null : _requestPermission,
          child: _requesting
              ? const CommonCircleLoading(size: 16)
              : Text(context.l10n.commonGrantPermission),
        ),
      ),
    );
  }
}

/// The "nothing to pick" state every app picker shares: an empty inventory, or a
/// search/filter that matched no app. Kept beside [AppListErrorState] so the two states
/// stay in one place and every picker renders them identically.
class AppListEmptyState extends StatelessWidget {
  const AppListEmptyState({
    super.key,
    required this.label,
    this.description,
    this.illustration = NullStatusIllustration.apps,
    this.minHeight = 240,
  });

  final String label;
  final String? description;
  final NullStatusIllustration illustration;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return EmptyStateBox(
      minHeight: minHeight,
      child: NullStatus(
        label: label,
        description: description,
        illustration: illustration,
      ),
    );
  }
}
