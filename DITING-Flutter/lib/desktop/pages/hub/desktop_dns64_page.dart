/// The `hub` branch's DNS64 page: the IPv6-only transition synthesizer, its prefix list and the
/// protections the service applies on its own.
///
/// The old desktop console (`ResolveView.vue` and its `network/DNS64Panel.vue`) is the functional
/// blueprint. The page owns no synthesis logic: it reads `dns64` from `/api/v1/status`, posts the
/// whole form to `/api/v1/dns/dns64/configure`, and shows what the service re-reads.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:diting/desktop/data/api/desktop_dns64_providers.dart';
import 'package:diting/desktop/pages/hub/widgets/dns64_card.dart';
import 'package:diting/desktop/pages/home/desktop_dashboard.dart';
import 'package:diting/desktop/widgets/desktop_card_board.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopDns64Page extends ConsumerWidget {
  const DesktopDns64Page({super.key});

  static const path = '/hub/dns64';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopDns64Provider);
    final config = state.config;
    void retry() => ref.read(desktopDns64Provider.notifier).reload();
    return CommonScaffold(
      title: l10n.desktopDns64Title,
      actions: [
        IconButton(
          tooltip: l10n.desktopDns64Refresh,
          onPressed: state.saving ? null : retry,
          icon: state.isLoading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              : const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: config == null
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
                  cards: [Dns64Card(config: config, saving: state.saving)],
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
            label: l10n.desktopDns64LoadFailed,
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
