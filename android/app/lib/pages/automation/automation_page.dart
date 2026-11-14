/// Automation centre (A1 / A14): the rule list plus the audit timeline.
///
/// The list is a view over `automation_rule`; opening a row edits its condition-action document,
/// tapping the switch enables or pauses it. The timeline is the append-only `automation_event` log,
/// so "when and why did it fire" is answerable without the log tables.
library;

import 'package:diting_android/data/db/automation_models.dart';
import 'package:diting_android/routes/automation_routes.dart';
import 'package:diting_android/state/automation_providers.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class AutomationPage extends ConsumerWidget {
  const AutomationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(automationRulesProvider);
    final events = ref.watch(automationEventsProvider);
    return CommonScaffold(
      title: context.l10n.automationTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.automationAdd,
          onPressed: () => context.push(AutomationPaths.edit('new')),
          icon: const GlyphIcon(AppGlyphs.add),
        ),
      ],
      body: PageBody(
        children: [
          PageIntroCard(text: context.l10n.automationIntro),
          rules.when(
            data: (list) => list.isEmpty
                ? PageIntroCard(text: context.l10n.automationEmpty)
                : generateSection(
                    title: context.l10n.automationRulesSection,
                    items: [
                      for (final rule in list)
                        _RuleTile(
                          rule: rule,
                          onToggle: (value) => ref
                              .read(automationControllerProvider)
                              .setRuleEnabled(rule.id, value),
                          onTap: () => context.push(
                            AutomationPaths.edit(rule.id),
                          ),
                        ),
                    ],
                  ),
            loading: () => const SizedBox.shrink(),
            error: (error, _) => PageIntroCard(text: '$error'),
          ),
          events.when(
            data: (list) => generateSection(
              title: context.l10n.automationHistory,
              items: [
                if (list.isEmpty)
                  ListItem(
                    leading: const GlyphIcon(AppGlyphs.clock),
                    title: Text(context.l10n.automationHistoryEmpty),
                  )
                else
                  for (final event in list.take(30)) _EventTile(event: event),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (error, _) => PageIntroCard(text: '$error'),
          ),
        ],
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({
    required this.rule,
    required this.onToggle,
    required this.onTap,
  });

  final AutomationRule rule;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: GlyphIcon(
        rule.triggerType == AutomationSpec.triggerSchedule
            ? AppGlyphs.clock
            : AppGlyphs.connections,
      ),
      title: Text(
        rule.name.isEmpty ? context.l10n.automationRuleFallbackName : rule.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_triggerLabel(context, rule.triggerType)} · '
        '${context.l10n.automationPriorityShort(rule.priority)} · '
        '${context.l10n.automationActionCount(rule.actions.length)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Switch(value: rule.enabled, onChanged: onToggle),
      onTap: onTap,
    );
  }

  static String _triggerLabel(BuildContext context, String type) => switch (type) {
    AutomationSpec.triggerSchedule => context.l10n.automationTriggerSchedule,
    AutomationSpec.triggerNetwork => context.l10n.automationTriggerNetwork,
    AutomationSpec.triggerState => context.l10n.automationTriggerState,
    _ => context.l10n.automationTriggerManual,
  };
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final AutomationEvent event;

  @override
  Widget build(BuildContext context) {
    final when = DateTime.fromMillisecondsSinceEpoch(event.ts);
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${two(when.month)}-${two(when.day)} ${two(when.hour)}:${two(when.minute)}';
    return ListItem(
      leading: const GlyphIcon(AppGlyphs.checkCircle),
      title: Text('$stamp · ${event.event}'),
      subtitle: Text(
        event.outcome.isEmpty ? event.ruleId : event.outcome,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
