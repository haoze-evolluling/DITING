/// Desktop home: upstream FlClash's dashboard board, fed by the local service API.
///
/// The page owns no state of its own beyond what the snapshot says. Three honest shapes: the first
/// load, an unreachable or unauthorized service, and the board. A failed poll after a good one
/// keeps the last figures and says they are stale.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/pages/home/desktop_dashboard.dart';
import 'package:diting_desktop/pages/home/widgets/desktop_power_button.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopHomePage extends ConsumerWidget {
  const DesktopHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(desktopStatusProvider);
    final value = snapshot.status;
    final config = ref.watch(desktopApiConfigProvider);
    ref.listen(desktopControlProvider, (previous, next) {
      final error = next.error;
      if (error == null || error == previous?.error) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.l10n.desktopActionFailed(error.message)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });

    final error = snapshot.error;
    return CommonScaffold(
      title: context.l10n.bottomBarHome,
      actions: [if (value != null) DesktopPowerButton(status: value)],
      body: value != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (snapshot.isStale)
                  StaleStatusNotice(
                    onRetry: () =>
                        ref.read(desktopStatusProvider.notifier).refresh(),
                  ),
                Expanded(child: DesktopDashboardBoard(status: value)),
              ],
            )
          : snapshot.isLoading
          ? const Center(child: CommonCircleLoading.page())
          : _BackendNotice(
              unauthorized: error is DesktopApiException && error.unauthorized,
              address: '${config.host}:${config.port}',
              onRetry: () => ref.invalidate(desktopStatusProvider),
            ),
    );
  }
}

/// The service never answered: say which address was tried, so the fix (start it, or point the app
/// at another port) is obvious from the screen.
class _BackendNotice extends StatelessWidget {
  const _BackendNotice({
    required this.unauthorized,
    required this.address,
    required this.onRetry,
  });

  final bool unauthorized;
  final String address;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppBarClearance(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: NullStatus(
            illustration: unauthorized
                ? NullStatusIllustration.permission
                : NullStatusIllustration.error,
            label: unauthorized
                ? l10n.desktopBackendUnauthorizedTitle
                : l10n.desktopBackendOfflineTitle,
            description: unauthorized
                ? l10n.desktopBackendUnauthorizedBody
                : l10n.desktopBackendOfflineBody(address),
            action: FilledButton.tonal(
              onPressed: onRetry,
              child: Text(l10n.desktopRetry),
            ),
          ),
        ),
      ),
    );
  }
}
