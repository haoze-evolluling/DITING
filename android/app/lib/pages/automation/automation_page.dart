/// Automation centre (A1 / A14): the rule list, the scenario settings (including the merged
/// on-demand connection) and the audit timeline.
///
/// The list is a view over `automation_rule`; opening a row edits its condition-action document,
/// tapping the switch enables or pauses it. The timeline is the append-only `automation_event` log,
/// so "when and why did it fire" is answerable without the log tables. On-demand used to live under
/// 自定义资源; it is now a section here because it is another way a scenario decides the tunnel.
///
/// Layout: one overview card states the rule situation at a glance (or invites the first rule), then
/// a single grouped surface holds every scenario setting, with the rules and the timeline as their
/// own sections. The page reads top-down — overview, then inputs, then history — instead of a stack
/// of equally-weighted cards.
library;

import 'package:diting_android/data/db/automation_models.dart';
import 'package:diting_android/routes/automation_routes.dart';
import 'package:diting_android/routes/network_profile_routes.dart';
import 'package:diting_android/state/automation_providers.dart';
import 'package:diting_android/state/config_providers_resources.dart';
import 'package:diting_android/widgets/icon_badge.dart';
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
    final resources = ref.watch(configResourcesProvider);
    final list = rules.asData?.value;
    final l10n = context.l10n;
    return CommonScaffold(
      title: l10n.automationTitle,
      actions: [
        IconButton(
          tooltip: l10n.automationAdd,
          onPressed: () => context.push(AutomationPaths.edit('new')),
          icon: const GlyphIcon(AppGlyphs.add),
        ),
      ],
      body: PageBody(
        children: [
          // The explainer reads as page-level help, not a surface of its own, so the overview below
          // is the first card the eye lands on. It used to be a card stacked on the empty card.
          PageIntroText(text: l10n.automationIntro),
          if (list != null)
            _AutomationOverview(
              total: list.length,
              enabled: list.where((rule) => rule.enabled).length,
              onCreate: () => context.push(AutomationPaths.edit('new')),
            )
          else if (rules.hasError)
            PageIntroText(text: '${rules.error}'),
          // The rules themselves, only when there are some: the overview already covers "none".
          if (list != null && list.isNotEmpty)
            generateSection(
              title: l10n.automationRulesSection,
              items: [
                for (final rule in list)
                  _RuleTile(
                    rule: rule,
                    onToggle: (value) => ref
                        .read(automationControllerProvider)
                        .setRuleEnabled(rule.id, value),
                    onTap: () => context.push(AutomationPaths.edit(rule.id)),
                  ),
              ],
            ),
          // One grouped surface for every scenario setting. The on-demand connection and the three
          // entry points used to be two separate, separately-headed sections; they belong together.
          generateSection(
            title: l10n.automationSettingsSection,
            items: [
              _NavRow(
                glyph: AppGlyphs.wifi,
                title: l10n.odTitle,
                subtitle: resources.onDemand
                    ? '${l10n.odAllowlist} · '
                          '${l10n.configItemCount(resources.ssidRules.length)}'
                    : l10n.odDisableBody,
                onTap: () => context.push(AutomationPaths.onDemand),
              ),
              _NavRow(
                glyph: AppGlyphs.profiles,
                title: l10n.profilesTitle,
                subtitle: l10n.profilesSubtitle,
                onTap: () => context.push(AutomationPaths.profiles),
              ),
              _NavRow(
                glyph: AppGlyphs.calendar,
                title: l10n.timetableTitle,
                subtitle: l10n.timetableSubtitle,
                onTap: () => context.push(AutomationPaths.timetable),
              ),
              _NavRow(
                glyph: AppGlyphs.network,
                title: l10n.netProfileTitle,
                subtitle: l10n.netProfileSubtitle,
                onTap: () => context.push(NetworkProfilePaths.root),
              ),
            ],
          ),
          events.when(
            data: (list) => generateSection(
              title: l10n.automationHistory,
              items: [
                if (list.isEmpty)
                  ListItem(
                    leading: const GlyphIcon(AppGlyphs.clock),
                    title: Text(l10n.automationHistoryEmpty),
                  )
                else
                  for (final event in list.take(30)) _EventTile(event: event),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (error, _) => PageIntroText(text: '$error'),
          ),
        ],
      ),
    );
  }
}

/// The page's focal card: a live summary of the rule set, or a first-run invitation when there are
/// none. It gives the page a headline to hang its sections under, which the old flat "intro card +
/// empty card" pair never did.
class _AutomationOverview extends StatelessWidget {
  const _AutomationOverview({
    required this.total,
    required this.enabled,
    required this.onCreate,
  });

  final int total;
  final int enabled;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = context.colorScheme;
    final empty = total == 0;
    // Invite when empty, confirm while any rule is active, stay neutral when all are paused.
    final Color accent;
    if (empty) {
      accent = scheme.primary;
    } else if (enabled > 0) {
      accent = scheme.success;
    } else {
      accent = scheme.onSurfaceVariant;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: CommonCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        child: Row(
          spacing: 12,
          children: [
            IconBadge(
              glyph: empty ? AppGlyphs.automation : AppGlyphs.rules,
              color: accent.withValues(alpha: 0.14),
              foregroundColor: accent,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text(
                    empty
                        ? l10n.automationOverviewEmptyTitle
                        : l10n.automationOverviewSummary(total, enabled),
                    style: AppTextRole.cardTitle
                        .of(context)
                        .copyWith(color: scheme.onSurface),
                  ),
                  Text(
                    empty
                        ? l10n.automationOverviewEmptyHint
                        : l10n.automationOverviewHint,
                    style: AppTextRole.supportingText.of(context),
                  ),
                ],
              ),
            ),
            if (empty)
              TextButton(onPressed: onCreate, child: Text(l10n.automationAdd)),
          ],
        ),
      ),
    );
  }
}

/// A settings row that pushes another page.
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Glyph glyph;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: GlyphIcon(glyph),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const GlyphIcon(AppGlyphs.chevronForward, size: 18),
      onTap: onTap,
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
            : AppGlyphs.automation,
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
      trailing: CommonSwitch(value: rule.enabled, onChanged: onToggle),
      onTap: onTap,
    );
  }

  static String _triggerLabel(BuildContext context, String type) =>
      switch (type) {
        AutomationSpec.triggerSchedule =>
          context.l10n.automationTriggerSchedule,
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
