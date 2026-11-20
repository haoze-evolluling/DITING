library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_custom_rules_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_custom_rules_card.dart';
import 'package:diting_desktop/pages/home/desktop_dashboard.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopFilterRulesPage extends ConsumerWidget {
  const DesktopFilterRulesPage({super.key});

  static const path = '/hub/filter-rules';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopCustomRulesProvider);
    void retry() => ref.read(desktopCustomRulesProvider.notifier).reload();
    return CommonScaffold(
      title: l10n.desktopFilterRulesPageTitle,
      actions: [
        IconButton(
          tooltip: l10n.desktopFilterRulesRefresh,
          onPressed: state.saving ? null : retry,
          icon: state.isLoading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              : const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: PageBody(
        children: [
          state.isStale
              ? StaleStatusNotice(onRetry: retry)
              : const SizedBox.shrink(),
          const DesktopCardBoard(
            cards: [CustomRulesEditorCard(), RuleSyntaxGuideCard()],
          ),
        ],
      ),
    );
  }
}
