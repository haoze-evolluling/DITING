/// The `hub` branch's app blocking page: the group shortcuts, the built-in service catalogue, the
/// search and group filters, the selection and each service's weekly plan.
///
/// The old desktop console (`ProtectView.vue` and its `ServicesPanel`) is the functional blueprint.
/// The page owns no blocking logic: it reads `/api/v1/filter/services` and adopts the whole state the
/// service answers with after every write.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_services_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/blocked_services_card.dart';
import 'package:diting_desktop/pages/hub/widgets/blocked_services_groups_card.dart';
import 'package:diting_desktop/pages/home/desktop_dashboard.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopServicesPage extends ConsumerWidget {
  const DesktopServicesPage({super.key});

  static const path = '/hub/filter-services';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopServicesProvider);
    void retry() => ref.read(desktopServicesProvider.notifier).reload();
    return CommonScaffold(
      title: l10n.desktopServicesPageTitle,
      actions: [
        IconButton(
          tooltip: l10n.desktopServicesRefresh,
          onPressed: state.saving ? null : retry,
          icon: state.isLoading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              : const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: state.data == null && !state.isLoading && state.error != null
          ? _Unavailable(error: state.error!, onRetry: retry)
          : PageBody(
              children: [
                state.isStale
                    ? StaleStatusNotice(onRetry: retry)
                    : const SizedBox.shrink(),
                const DesktopCardBoard(
                  cards: [
                    BlockedServiceGroupsCard(),
                    BlockedServicesCard(),
                  ],
                ),
              ],
            ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.error, required this.onRetry});

  final DesktopApiException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppBarClearance(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: NullStatus(
            illustration: error.unauthorized
                ? NullStatusIllustration.permission
                : NullStatusIllustration.error,
            label: l10n.desktopServicesLoadFailed,
            description: error.unauthorized
                ? l10n.desktopBackendUnauthorizedBody
                : error.message,
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
