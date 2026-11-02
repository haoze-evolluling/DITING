/// Desktop home: the dashboard, the device list and the log dashboard on one page.
///
/// The page owns no state of its own beyond what the snapshots say. Three honest shapes: the first
/// load, an unreachable or unauthorized service, and the board. A failed poll after a good one
/// keeps the last figures and says they are stale. The three sections share one board and one
/// refresh, because they answer the same question — what is the service doing right now — from
/// three angles, and a window has room for all of them.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_models.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_log_providers.dart';
import 'package:diting_desktop/data/api/desktop_traffic_providers.dart';
import 'package:diting_desktop/pages/home/desktop_dashboard.dart';
import 'package:diting_desktop/pages/home/widgets/desktop_power_button.dart';
import 'package:diting_desktop/pages/logs/desktop_logs_section.dart';
import 'package:diting_desktop/pages/traffic/desktop_traffic_section.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopHomePage extends ConsumerWidget {
  const DesktopHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(desktopStatusProvider);
    final value = snapshot.status;
    final config = ref.watch(desktopApiConfigProvider);

    /// One refresh for the whole page: each section polls on its own, but a reader who just
    /// changed something on another page expects this button to re-read all of them at once.
    void refreshAll() {
      ref.read(desktopStatusProvider.notifier).refresh();
      ref.read(desktopTrafficProvider.notifier).reload();
      ref.read(desktopQueryStatsProvider.notifier).refresh();
      ref.invalidate(desktopLogFeedProvider);
    }

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
      actions: [
        IconButton(
          tooltip: context.l10n.logsRefresh,
          onPressed: refreshAll,
          icon: const GlyphIcon(AppGlyphs.refresh),
        ),
        if (value != null) DesktopPowerButton(status: value),
      ],
      body: value != null
          ? _HomeBoard(status: value, stale: snapshot.isStale, onRefresh: refreshAll)
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

/// The board itself, once the status snapshot exists. It is a separate widget so the device and
/// log providers are only read when there is a board to put their cards on: a window that cannot
/// reach the service shows one notice instead of three failed sections.
class _HomeBoard extends ConsumerWidget {
  const _HomeBoard({
    required this.status,
    required this.stale,
    required this.onRefresh,
  });

  final DesktopStatus status;

  /// The status snapshot answered before but its last poll failed.
  final bool stale;

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traffic = ref.watch(desktopTrafficProvider);
    return PageBody(
      children: [
        // The summary card and the client card speak for their own failed reads; this notice is
        // about the two snapshots that keep showing their previous figures without a hint.
        if (stale || traffic.isStale) StaleStatusNotice(onRetry: onRefresh),
        DashboardDensityScopeHost(
          child: DesktopCardBoard(
            cards: [
              ...desktopDashboardCards(status),
              ...desktopTrafficCards(context, ref),
              ...desktopLogCards(context, ref),
            ],
          ),
        ),
      ],
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
