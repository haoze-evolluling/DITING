/// The `hub` branch's rewrite page: the engine switch, the default lifetime and the rule table.
///
/// The old desktop console (`ResolveView.vue` and its `rules/RewritePanel.vue`) is the functional
/// blueprint. The page owns no matching logic: it reads `/status` and `/dns/rewrite/rules`, posts a
/// switch, a lifetime or one rule, and shows what the service re-reads.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:diting/desktop/data/api/desktop_rewrite_providers.dart';
import 'package:diting/desktop/pages/home/desktop_dashboard.dart';
import 'package:diting/desktop/pages/hub/widgets/rewrite_engine_card.dart';
import 'package:diting/desktop/pages/hub/widgets/rewrite_rules_card.dart';
import 'package:diting/desktop/pages/hub/widgets/zone_file_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const double _contentMaxWidth = 1200;

class DesktopRewritePage extends ConsumerWidget {
  const DesktopRewritePage({super.key});

  static const path = '/hub/rewrite';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopRewriteProvider);
    final config = state.config;
    void retry() => ref.read(desktopRewriteProvider.notifier).reload();
    return CommonScaffold(
      title: l10n.desktopRewriteTitle,
      actions: [
        IconButton(
          tooltip: l10n.logsRefresh,
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
                if (state.error != null) StaleStatusNotice(onRetry: retry),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _contentMaxWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: dashboardCardGap,
                        children: [
                          RewriteEngineCard(
                            config: config,
                            saving: state.saving,
                          ),
                          RewriteRulesCard(
                            config: config,
                            saving: state.saving,
                          ),
                          const ZoneFileCard(),
                        ],
                      ),
                    ),
                  ),
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
            label: l10n.desktopRewriteLoadFailed,
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
