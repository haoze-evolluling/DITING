/// The `traffic` branch's device page: who queried, under which name, and what the ACL and rate
/// limit allow.
///
/// The old desktop console's `DevicesView.vue` → `ClientsPanel` is the functional blueprint. There is
/// no per-application traffic here: the old console never measured it, and this page does not invent
/// it. The branch keeps Android's tab label and path, so switching tabs behaves the same way.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_traffic_providers.dart';
import 'package:diting_desktop/pages/traffic/widgets/client_access_card.dart';
import 'package:diting_desktop/pages/traffic/widgets/client_list_card.dart';
import 'package:diting_desktop/pages/traffic/widgets/client_rate_limit_card.dart';
import 'package:diting_desktop/pages/home/desktop_dashboard.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopTrafficPage extends ConsumerWidget {
  const DesktopTrafficPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopTrafficProvider);
    final limits = state.limits;
    void retry() => ref.read(desktopTrafficProvider.notifier).reload();
    return CommonScaffold(
      title: l10n.desktopTrafficPageTitle,
      actions: [
        IconButton(
          tooltip: l10n.desktopTrafficRefresh,
          onPressed: state.saving ? null : retry,
          icon: state.isLoading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              : const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: limits == null
          ? _Unavailable(
              loading: state.isLoading,
              error: state.error,
              onRetry: retry,
            )
          : PageBody(
              children: [
                state.isStale
                    ? StaleStatusNotice(onRetry: retry)
                    : const SizedBox.shrink(),
                DesktopCardBoard(
                  cards: [
                    DesktopClientListCard(
                      clients: state.clients,
                      access: limits.access,
                      saving: state.saving,
                      loading: state.isLoading,
                      onRefresh: retry,
                    ),
                    ClientAccessCard(
                      access: limits.access,
                      saving: state.saving,
                    ),
                    ClientRateLimitCard(
                      rateLimit: limits.rateLimit,
                      saving: state.saving,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final DesktopApiException? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (loading) return const Center(child: CommonCircleLoading.page());
    final unauthorized = error?.unauthorized ?? false;
    return AppBarClearance(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: NullStatus(
            illustration: unauthorized
                ? NullStatusIllustration.permission
                : NullStatusIllustration.error,
            label: l10n.desktopTrafficLoadFailed,
            description: unauthorized
                ? l10n.desktopBackendUnauthorizedBody
                : error?.message,
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
