// ignore_for_file: sort_child_properties_last
import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/db/mirror_template_repository.dart';
import 'package:diting/data/db/subscription_models.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/pages/hub/mirror_global_section.dart';
import 'package:diting/state/auto_update_providers.dart';
import 'package:diting/state/auto_update_runner.dart';
import 'package:diting/state/global_mirror_providers.dart';
import 'package:diting/state/subscription_providers.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/page_intro.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

part 'mirror_templates_page.dart';

/// Subscription auto-update (upstream `SubscriptionAutoUpdateIntervalScreen`). No local state: the
/// switch and interval live in `subscription_auto_update_enabled` / `..._interval_hours`.
class AutoUpdateSettingsPage extends ConsumerWidget {
  const AutoUpdateSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(autoUpdateSettingsProvider);
    final groups = ref.watch(autoUpdateGroupsProvider).value;
    final actions = ref.read(autoUpdateActionsProvider);
    final candidates = ref.watch(autoUpdatableSubscriptionsProvider).value;
    final lastRun = ref.watch(autoUpdateLastRunProvider);
    final enabled = settings.enabled;
    final interval = settings.schedule == AutoUpdateSchedule.interval;
    return CommonScaffold(
      title: context.l10n.autoUpdateTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.autoUpdateSection,
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.refresh),
                title: Text(context.l10n.autoUpdateRulesSwitch),
                subtitle: Text(context.l10n.autoUpdateRulesSwitchSubtitle),
                value: enabled,
                onChanged: actions.setEnabled,
              ),
            ],
          ),
          generateSection(
            title: context.l10n.autoUpdateIntervalSection,
            items: [
              for (final hours
                  in LegacySettings.subscriptionAutoUpdatePresetHours)
                ListItem(
                  leading: GlyphIcon(
                    interval && settings.intervalHours == hours
                        ? AppGlyphs.checkCircle
                        : AppGlyphs.clock,
                    size: 20,
                  ),
                  title: Text(context.l10n.autoUpdateEveryHours(hours)),
                  trailing: interval && settings.intervalHours == hours
                      ? const SelectionCheck()
                      : null,
                  onTap: enabled ? () => actions.setIntervalHours(hours) : null,
                ),
              ListItem(
                leading: GlyphIcon(
                  interval && settings.isCustom
                      ? AppGlyphs.checkCircle
                      : AppGlyphs.sliders,
                  size: 20,
                ),
                title: Text(context.l10n.autoUpdateCustomInterval),
                subtitle: Text(
                  settings.isCustom
                      ? context.l10n.autoUpdateEveryHours(
                          settings.intervalHours,
                        )
                      : context.l10n.autoUpdateCustomHint,
                ),
                trailing: interval && settings.isCustom
                    ? const SelectionCheck()
                    : null,
                onTap: enabled
                    ? () => _editCustom(context, ref, settings)
                    : null,
              ),
            ],
          ),
          generateSection(
            title: context.l10n.autoUpdateTimedSection,
            items: [
              for (final schedule in const [
                AutoUpdateSchedule.daily,
                AutoUpdateSchedule.everyOtherDay,
              ])
                ListItem(
                  leading: GlyphIcon(
                    settings.schedule == schedule
                        ? AppGlyphs.checkCircle
                        : AppGlyphs.clock,
                    size: 20,
                  ),
                  title: Text(
                    schedule == AutoUpdateSchedule.daily
                        ? context.l10n.autoUpdateDailyAt(
                            _clock(settings.timeMinutes),
                          )
                        : context.l10n.autoUpdateEveryOtherDayAt(
                            _clock(settings.timeMinutes),
                          ),
                  ),
                  subtitle: Text(
                    settings.schedule == schedule
                        ? context.l10n.autoUpdateTimedChangeHint
                        : context.l10n.autoUpdateTimedPickHint,
                  ),
                  trailing: settings.schedule == schedule
                      ? const SelectionCheck()
                      : null,
                  onTap: enabled
                      ? () => _pickTime(context, ref, settings, schedule)
                      : null,
                ),
            ],
            footer: context.l10n.autoUpdateIntervalFooter,
          ),
          generateSection(
            title: context.l10n.autoUpdateStatusSection,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.clock),
                title: Text(context.l10n.autoUpdateNext),
                subtitle: Text(
                  _nextUpdateText(context.l10n, enabled, settings, candidates),
                ),
              ),
              ListItem(
                leading: GlyphIcon(
                  lastRun == null ? AppGlyphs.info : AppGlyphs.checkCircle,
                  size: 20,
                ),
                title: Text(context.l10n.autoUpdateLast),
                subtitle: Text(
                  lastRun == null
                      ? context.l10n.autoUpdateNoRunYet
                      : '${lastRun.summary ?? ''}'
                            '${context.l10n.autoUpdateRunCount(lastRun.ranCount)}',
                ),
              ),
            ],
            footer: context.l10n.autoUpdateStatusFooter,
          ),
          generateSection(
            title: context.l10n.autoUpdateGroupsSection,
            items: [
              if (groups == null)
                ListItem(
                  leading: GlyphIcon(AppGlyphs.layers),
                  title: Text(context.l10n.autoUpdateReadingGroups),
                )
              else if (groups.isEmpty)
                ListItem(
                  leading: GlyphIcon(AppGlyphs.layers),
                  title: Text(context.l10n.autoUpdateNoGroups),
                  subtitle: Text(context.l10n.autoUpdateNoGroupsSubtitle),
                )
              else
                for (final group in groups)
                  ListItem.toggle(
                    leading: const GlyphIcon(AppGlyphs.layers),
                    title: Text(group.name),
                    value: group.autoUpdateEnabled,
                    onChanged: enabled
                        ? (value) => actions.setGroupEnabled(group.id, value)
                        : null,
                  ),
            ],
            footer: context.l10n.autoUpdateGroupsFooter,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _editCustom(
    BuildContext context,
    WidgetRef ref,
    AutoUpdateSettings settings,
  ) async {
    final value = await showFloatingDialog<int>(
      context: context,
      child: _IntervalDialog(initial: settings.intervalHours),
    );
    if (value != null) {
      ref.read(autoUpdateActionsProvider).setIntervalHours(value);
    }
  }

  /// Opens the system time picker; the chosen wall-clock time follows the phone's time zone.
  Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref,
    AutoUpdateSettings settings,
    AutoUpdateSchedule schedule,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: settings.timeMinutes ~/ 60,
        minute: settings.timeMinutes % 60,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    ref
        .read(autoUpdateActionsProvider)
        .setTimedSchedule(schedule, picked.hour * 60 + picked.minute);
  }

  static String _clock(int minutes) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(minutes ~/ 60)}:${two(minutes % 60)}';
  }

  /// The "next update" line, covering switch off, no candidates and the earliest due one;
  /// [AutoUpdatePlan.nextDueAt] derives it from the real `lastAttemptAt`.
  String _nextUpdateText(
    AppL10n l10n,
    bool enabled,
    AutoUpdateSettings settings,
    List<SubscriptionRecord>? candidates,
  ) {
    if (!enabled) {
      return l10n.autoUpdateDisabled;
    }
    if (candidates == null) {
      return l10n.autoUpdateReadingSubs;
    }
    if (candidates.isEmpty) {
      return l10n.autoUpdateNoCandidates;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = settings.plan.nextDueAt(candidates, now);
    if (due == null) {
      return l10n.autoUpdateNoSubscriptions;
    }
    if (due <= now) {
      return l10n.autoUpdateDueNow;
    }
    final when = DateTime.fromMillisecondsSinceEpoch(due);
    final remaining = due - now;
    final hours = remaining ~/ 3600000;
    final minutes = (remaining % 3600000) ~/ 60000;
    final left = hours > 0
        ? l10n.autoUpdateRemainingHours(hours, minutes)
        : l10n.autoUpdateRemainingMinutes(minutes);
    return l10n.autoUpdateNextAt(_formatMoment(when, l10n), left);
  }

  static String _formatMoment(DateTime time, AppL10n l10n) {
    String two(int value) => value.toString().padLeft(2, '0');
    return l10n.autoUpdateMoment(
      time.month,
      time.day,
      '${two(time.hour)}:${two(time.minute)}',
    );
  }
}

/// Custom interval dialog. The controller is owned by the dialog: disposing it right after
/// `await` trips a framework assertion while the exit animation still shows the `TextField`.
class _IntervalDialog extends StatefulWidget {
  const _IntervalDialog({required this.initial});

  final int initial;

  @override
  State<_IntervalDialog> createState() => _IntervalDialogState();
}

class _IntervalDialogState extends State<_IntervalDialog> {
  late final _controller = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = int.tryParse(_controller.text);
    if (parsed == null ||
        parsed < LegacySettings.minSubscriptionAutoUpdateIntervalHours ||
        parsed > LegacySettings.maxSubscriptionAutoUpdateIntervalHours) {
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: context.l10n.autoUpdateCustomInterval,
      hasFields: true,
      child: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: context.l10n.autoUpdateIntervalLabel,
          helperText: context.l10n.autoUpdateIntervalHelper,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.uiCancel),
        ),
        TextButton(onPressed: _submit, child: Text(context.l10n.commonSave)),
      ],
    );
  }
}
