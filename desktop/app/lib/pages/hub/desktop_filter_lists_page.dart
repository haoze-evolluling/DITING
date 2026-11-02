/// The `hub` branch's subscription lists: the engine's counters, the lists themselves and the four
/// per-list writes (add, toggle, refresh, delete).
///
/// The old desktop console (`ProtectView.vue` and its `RuleListsPanel`) is the functional blueprint.
/// The page owns no rule logic: it reads `/api/v1/filter/stats` and `/api/v1/filter/lists`, and each
/// write re-reads both so a rejected change never stays on screen.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_filter_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_lists_card.dart';
import 'package:diting_desktop/pages/home/desktop_dashboard.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopFilterListsPage extends ConsumerWidget {
  const DesktopFilterListsPage({super.key});

  static const path = '/hub/filter-lists';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopFilterListsProvider);
    void retry() => ref.read(desktopFilterListsProvider.notifier).reload();
    return CommonScaffold(
      title: l10n.desktopFilterListsPageTitle,
      actions: [
        IconButton(
          tooltip: l10n.desktopFilterListsRefresh,
          onPressed: state.saving ? null : retry,
          icon: state.isLoading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              : const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: state.isLoading && state.lists.total == 0
          ? const Center(child: CommonCircleLoading.page())
          : state.error != null && state.lists.total == 0
          ? _Unavailable(error: state.error!, onRetry: retry)
          : PageBody(
              children: [
                state.isStale
                    ? StaleStatusNotice(onRetry: retry)
                    : const SizedBox.shrink(),
                DesktopCardBoard(
                  cards: [
                    FilterSummaryCard(summary: state.summary),
                    const FilterListsCard(),
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
            label: l10n.desktopFilterListsLoadFailed,
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
