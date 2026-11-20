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

  final String error;

  final double minHeight;

  @override
  ConsumerState<AppListErrorState> createState() => _AppListErrorStateState();
}

class _AppListErrorStateState extends ConsumerState<AppListErrorState>
    with WidgetsBindingObserver {
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
