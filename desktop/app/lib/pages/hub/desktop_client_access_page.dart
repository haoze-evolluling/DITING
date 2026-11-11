/// The `hub` branch's client access page: who may resolve through this host, and how fast.
///
/// The page is the home board's old access cards, moved where a setting belongs: the dashboard only
/// reports figures now, so the allow/block lists and the token bucket live here. Both are the old
/// desktop console's `ClientsPanel.vue` → access and rate-limit cards; nothing is derived locally,
/// and every save posts the whole document and shows what the service re-read.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_traffic_providers.dart';
import 'package:diting_desktop/pages/home/desktop_dashboard.dart';
import 'package:diting_desktop/pages/traffic/widgets/client_access_card.dart';
import 'package:diting_desktop/pages/traffic/widgets/client_rate_limit_card.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopClientAccessPage extends ConsumerWidget {
  const DesktopClientAccessPage({super.key});

  static const path = '/hub/client-access';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopTrafficProvider);
    final limits = state.limits;
    void retry() => ref.read(desktopTrafficProvider.notifier).reload();
    return CommonScaffold(
      title: l10n.desktopClientAccessPageTitle,
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
