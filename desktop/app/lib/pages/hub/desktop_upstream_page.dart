/// The `hub` branch's upstream page: scheduling mode, the configured servers, bootstrap DNS,
/// split-DNS routes and the independent fallback chain.
///
/// The old desktop console (`ResolveView.vue` and its `UpstreamPanel`) is the functional blueprint.
/// The page owns no DNS logic: every switch and form posts the whole config to
/// `/api/v1/upstream/configure` and then shows what the service re-reads.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_upstream_models.dart';
import 'package:diting_desktop/data/api/desktop_upstream_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/bootstrap_card.dart';
import 'package:diting_desktop/pages/hub/widgets/conditional_routes_card.dart';
import 'package:diting_desktop/pages/hub/widgets/fallback_chain_card.dart';
import 'package:diting_desktop/pages/hub/widgets/upstream_mode_card.dart';
import 'package:diting_desktop/pages/home/desktop_dashboard.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_desktop/pages/hub/widgets/upstream_nodes_card.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopUpstreamPage extends ConsumerWidget {
  const DesktopUpstreamPage({super.key});

  static const path = '/hub/upstream';

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    DesktopUpstreamConfig next,
  ) async {
    final l10n = context.l10n;
    final error = await ref.read(desktopUpstreamProvider.notifier).save(next);
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopUpstreamSaved
          : l10n.desktopUpstreamSaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopUpstreamProvider);
    final config = state.config;
    void retry() => ref.read(desktopUpstreamProvider.notifier).reload();
    void save(DesktopUpstreamConfig next) => _save(context, ref, next);
    void failed(String message) => showDesktopMessage(context, message);

    return CommonScaffold(
      title: l10n.desktopUpstreamTitle,
      actions: [
        IconButton(
          tooltip: l10n.logsRefresh,
          onPressed: state.saving
              ? null
              : () => ref.read(desktopUpstreamProvider.notifier).reload(),
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
          : LayoutBuilder(
              builder: (context, constraints) {
                final cards = <Widget>[
                  UpstreamModeCard(
                    config: config,
                    saving: state.saving,
                    onChanged: save,
                  ),
                  UpstreamNodesCard(
                    config: config,
                    saving: state.saving,
                    onChanged: save,
                    onSaveFailed: failed,
                  ),
                  BootstrapCard(
                    config: config,
                    saving: state.saving,
                    onChanged: save,
                    onSaveFailed: failed,
                  ),
                  FallbackChainCard(
                    config: config,
                    saving: state.saving,
                    onChanged: save,
                  ),
                  ConditionalRoutesCard(
                    routes: config.conditionalRoutes,
                    saving: state.saving,
                    onChanged: (routes) =>
                        save(config.copyWith(conditionalRoutes: routes)),
                  ),
                ];
                return PageBody(
                  children: [
                    if (state.isStale) StaleStatusNotice(onRetry: retry),
                    DesktopCardBoard(cards: cards),
                  ],
                );
              },
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
            label: l10n.desktopUpstreamLoadFailed,
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
