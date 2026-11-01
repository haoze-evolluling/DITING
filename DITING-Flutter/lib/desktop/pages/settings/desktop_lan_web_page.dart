/// The settings branch's LAN console page: whether the web console is reachable from the LAN, on which
/// port, and with which admin credential.
///
/// The old desktop console's `LanWebCard.vue` is the functional blueprint. The card never decides the
/// listen address or whether a firewall rule is needed; `/web/status` reports both.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:diting/desktop/data/api/desktop_web_providers.dart';
import 'package:diting/desktop/pages/settings/widgets/lan_web_card.dart';
import 'package:diting/desktop/widgets/desktop_card_board.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/desktop/pages/home/desktop_dashboard.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopLanWebPage extends ConsumerWidget {
  const DesktopLanWebPage({super.key});

  static const path = '/settings/lan-web';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopWebProvider);
    final status = state.status;
    void retry() => ref.read(desktopWebProvider.notifier).reload();
    return CommonScaffold(
      title: l10n.desktopLanWebPageTitle,
      actions: [
        IconButton(
          tooltip: l10n.desktopLanWebRefresh,
          onPressed: state.saving ? null : retry,
          icon: state.isLoading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              : const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: status == null
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
                  cards: [LanWebCard(status: status, saving: state.saving)],
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
            label: l10n.desktopLanWebLoadFailed,
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
