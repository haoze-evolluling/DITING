/// The `hub` branch's custom rules: the AdGuard syntax guide and the editor that replaces the whole
/// list on save.
///
/// The old desktop console (`ProtectView.vue`, `RulesPanel.vue` "custom" tab) is the functional
/// blueprint. The page owns no rule parsing: it reads `/api/v1/filter/rules`, posts the list to the
/// same endpoint, and shows the list the service re-reads.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_custom_rules_providers.dart';
import 'package:diting/desktop/pages/hub/widgets/filter_custom_rules_card.dart';
import 'package:diting/desktop/pages/home/desktop_dashboard.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Two cards side by side stop fitting below this; the console stacks them at the same width.
const double _wideBreakpoint = 980;
const double _contentMaxWidth = 1200;

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
          // A stable slot: inserting the notice only when stale would shift the editor's
          // position and rebuild its State, discarding a draft the user is still editing.
          state.isStale
              ? StaleStatusNotice(onRetry: retry)
              : const SizedBox.shrink(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final editor = const CustomRulesEditorCard();
                    final guide = const RuleSyntaxGuideCard();
                    if (constraints.maxWidth < _wideBreakpoint) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: dashboardCardGap,
                        children: [editor, guide],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: dashboardCardGap,
                      children: [
                        Expanded(child: editor),
                        Expanded(child: guide),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
