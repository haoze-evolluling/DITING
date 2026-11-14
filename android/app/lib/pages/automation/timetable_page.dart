/// The weekly timetable (A12 / R7): the schedule-triggered rules laid out per weekday.
///
/// A timetable entry is a normal automation rule whose trigger is `schedule` and whose action is
/// typically `block_services`; building one reuses the rule editor rather than a second editor. The
/// window (`days` / `startMin` / `endMin`) is read from the rule's `spec_json`.
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

class TimetablePage extends ConsumerWidget {
  const TimetablePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(automationRulesProvider);
    return CommonScaffold(
      title: context.l10n.timetableTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.timetableAdd,
          onPressed: () => context.push(AutomationPaths.edit('new')),
          icon: const GlyphIcon(AppGlyphs.add),
        ),
      ],
      body: PageBody(
        children: [
          PageIntroCard(text: context.l10n.timetableIntro),
          rules.when(
            data: (list) {
              final scheduled = [
                for (final rule in list)
                  if (rule.triggerType == AutomationSpec.triggerSchedule) rule,
              ];
              if (scheduled.isEmpty) {
                return PageIntroCard(text: context.l10n.timetableEmpty);
              }
              final narrow = MaterialLocalizations.of(context).narrowWeekdays;
              return Column(
                children: [
                  for (var iso = 1; iso <= 7; iso++)
                    _DaySection(
                      label: narrow[iso % 7],
                      rules: [
                        for (final rule in scheduled)
                          if (_window(rule).days.contains(iso)) rule,
                      ],
                    ),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (error, _) => PageIntroCard(text: '$error'),
          ),
        ],
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.label, required this.rules});

  final String label;
  final List<AutomationRule> rules;

  @override
  Widget build(BuildContext context) {
    return generateSection(
      title: label,
      items: [
        if (rules.isEmpty)
          ListItem(
            leading: const GlyphIcon(AppGlyphs.clock),
            title: Text('—'),
          )
        else
          for (final rule in rules)
            ListItem(
              leading: const GlyphIcon(AppGlyphs.block),
              title: Text(
                rule.name.isEmpty
                    ? context.l10n.automationRuleFallbackName
                    : rule.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(_window(rule).label(context)),
            ),
      ],
    );
  }
}

class _Window {
  const _Window({required this.days, required this.startMin, required this.endMin});

  final List<int> days;
  final int startMin;
  final int endMin;

  String label(BuildContext context) =>
      '${_clock(startMin)} – ${_clock(endMin)}';

  static String _clock(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

_Window _window(AutomationRule rule) {
  final trigger = rule.spec['trigger'];
  final raw = trigger is Map ? trigger['window'] : null;
  if (raw is Map) {
    final days = raw['days'];
    return _Window(
      days: [
        if (days is List)
          for (final day in days)
            if (day is num) day.toInt(),
      ],
      startMin: (raw['startMin'] as num?)?.toInt() ?? 0,
      endMin: (raw['endMin'] as num?)?.toInt() ?? (24 * 60),
    );
  }
  return const _Window(days: [], startMin: 0, endMin: 24 * 60);
}
