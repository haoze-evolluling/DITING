/// The `tools` branch: network diagnosis first, with the rule and lookup testers as sub-pages.
///
/// The old desktop console's `DiagnosticsPanel.vue` is the functional blueprint. Its emergency
/// network restore is a native call with no HTTP endpoint, so it is not offered here rather than
/// being faked.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_tools_providers.dart';
import 'package:diting/desktop/pages/tools/desktop_rule_check_page.dart';
import 'package:diting/desktop/pages/tools/widgets/port_diagnosis_card.dart';
import 'package:diting/desktop/widgets/desktop_card_board.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class DesktopToolsPage extends ConsumerWidget {
  const DesktopToolsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopPortCheckProvider);
    return CommonScaffold(
      title: l10n.toolDiagnostics,
      actions: [
        IconButton(
          tooltip: l10n.desktopToolsCheck,
          onPressed: state.busy
              ? null
              : () => ref.read(desktopPortCheckProvider.notifier).check(),
          icon: state.busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              : const GlyphIcon(AppGlyphs.search),
        ),
      ],
      body: PageBody(
        children: [
          DesktopCardBoard(
            cards: [
              PortDiagnosisCard(state: state),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListHeader(title: l10n.desktopToolsMoreSection),
                  generateGroup([
                    ListItem(
                      leading: const GlyphIcon(AppGlyphs.rules, size: 20),
                      title: Text(l10n.desktopToolsRulePageTitle),
                      subtitle: Text(l10n.desktopToolsRuleEntryBody),
                      trailing: const GlyphIcon(
                        AppGlyphs.chevronForward,
                        size: 18,
                      ),
                      onTap: () => context.push(DesktopRuleCheckPage.path),
                    ),
                  ]),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
