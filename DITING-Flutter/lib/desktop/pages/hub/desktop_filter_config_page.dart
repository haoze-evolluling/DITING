/// The `hub` branch's blocking mode page: the master switch, the three answer modes, the addresses
/// they return, the refresh interval, the temporary pause and the advanced switches.
///
/// The old desktop console (`ProtectView.vue`, `RulesPanel.vue` "config"/"advanced" tabs) is the
/// functional blueprint. The page owns no blocking logic: it reads `/filter/config`,
/// `/filter/stats` and `/filter/pause`, and every write re-reads them.
library;

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:diting/desktop/data/api/desktop_filter_config_models.dart';
import 'package:diting/desktop/data/api/desktop_filter_config_providers.dart';
import 'package:diting/desktop/data/api/desktop_filter_models.dart';
import 'package:diting/desktop/pages/hub/widgets/filter_advanced_card.dart';
import 'package:diting/desktop/pages/hub/widgets/filter_lists_card.dart';
import 'package:diting/desktop/pages/hub/widgets/filter_mode_card.dart';
import 'package:diting/desktop/pages/hub/widgets/filter_pause_card.dart';
import 'package:diting/desktop/pages/home/desktop_dashboard.dart';
import 'package:diting/desktop/widgets/desktop_feedback.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Two columns appear only once both cards still fit their fields; below this they stack.
const double _wideBreakpoint = 980;
const double _contentMaxWidth = 1200;

class DesktopFilterConfigPage extends ConsumerWidget {
  const DesktopFilterConfigPage({super.key});

  static const path = '/hub/filter-config';

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    DesktopFilterConfig config,
    bool enabled,
  ) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopFilterConfigProvider.notifier)
        .save(config.copyWith(enabled: enabled));
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (enabled
                ? l10n.desktopFilterEngineOnMessage
                : l10n.desktopFilterEngineOffMessage)
          : l10n.desktopFilterConfigSaveFailed(error.message),
    );
  }

  void _retry(WidgetRef ref) {
    unawaited(ref.read(desktopFilterConfigProvider.notifier).reload());
    unawaited(ref.read(desktopFilterPauseProvider.notifier).reload());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopFilterConfigProvider);
    final config = state.config;
    void retry() => _retry(ref);
    return CommonScaffold(
      title: l10n.desktopFilterConfigPageTitle,
      actions: [
        IconButton(
          tooltip: l10n.desktopFilterConfigRefresh,
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
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= _wideBreakpoint;
                final mode = FilterModeCard(
                  config: config,
                  saving: state.saving,
                );
                final side = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: dashboardCardGap,
                  children: [
                    const FilterPauseCard(),
                    FilterAdvancedCard(
                      config: config,
                      saving: state.saving,
                    ),
                  ],
                );
                return PageBody(
                  children: [
                    state.isStale
                        ? StaleStatusNotice(onRetry: retry)
                        : const SizedBox.shrink(),
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
                              FilterSummaryCard(
                                summary:
                                    state.summary ??
                                    DesktopFilterSummary.empty,
                                saving: state.saving,
                                onToggle: (value) => unawaited(
                                  _toggle(context, ref, config, value),
                                ),
                              ),
                              if (wide)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  spacing: dashboardCardGap,
                                  children: [
                                    Expanded(child: mode),
                                    Expanded(child: side),
                                  ],
                                )
                              else ...[
                                mode,
                                side,
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
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
            label: l10n.desktopFilterConfigLoadFailed,
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
