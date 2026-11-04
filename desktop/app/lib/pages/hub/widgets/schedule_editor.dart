/// The schedule editor shared by the global time plan and a single service's weekly plan.
///
/// The old desktop console's `ScheduleEditor.vue` is the blueprint: one block per window with a
/// name, a switch, two `HH:MM` clocks and seven weekday toggles (none means every day). Rows are a
/// local draft; the page decides when to save them.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_schedule_models.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class ScheduleEditor extends StatefulWidget {
  const ScheduleEditor({
    super.key,
    required this.rows,
    required this.onChanged,
    this.disabled = false,
  });

  final List<DesktopSchedule> rows;
  final ValueChanged<List<DesktopSchedule>> onChanged;
  final bool disabled;

  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  final _drafts = <_ScheduleDraft>[];
  List<DesktopSchedule>? _adopted;
  int _nextKey = 0;

  @override
  void initState() {
    super.initState();
    _adopt(widget.rows);
  }

  @override
  void didUpdateWidget(ScheduleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _adopt(widget.rows);
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _adopt(List<DesktopSchedule> rows) {
    if (identical(_adopted, rows)) return;
    _adopted = rows;
    for (final draft in _drafts) {
      draft.dispose();
    }
    _drafts
      ..clear()
      ..addAll([for (final row in rows) _ScheduleDraft.from(row, _nextKey++)]);
  }

  void _emit() {
    final rows = [for (final draft in _drafts) draft.export()];
    widget.onChanged(rows);
  }

  /// A switch or a weekday changes what is drawn, so the editor repaints before telling the page.
  void _refresh() {
    setState(() {});
    _emit();
  }

  void _add() {
    setState(() {
      _drafts.add(
        _ScheduleDraft(
          key: _nextKey++,
          id: '',
          name: '',
          enabled: true,
          weekdays: const [],
          start: '08:00',
          end: '18:00',
        ),
      );
    });
    _emit();
  }

  Future<void> _remove(_ScheduleDraft draft) async {
    final l10n = context.l10n;
    final confirmed = await confirmDesktopAction(
      context,
      title: l10n.desktopScheduleDeleteTitle,
      body: l10n.desktopScheduleDeleteBody,
      confirmLabel: l10n.desktopScheduleDeleteConfirm,
    );
    if (!confirmed || !mounted) return;
    setState(() => _drafts.remove(draft));
    draft.dispose();
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        for (final draft in _drafts)
          _ScheduleRow(
            key: ValueKey(draft.key),
            draft: draft,
            disabled: widget.disabled,
            onChanged: _emit,
            onStructureChanged: _refresh,
            onDelete: () => _remove(draft),
          ),
        OutlinedButton.icon(
          onPressed: widget.disabled ? null : _add,
          icon: const GlyphIcon(AppGlyphs.add, size: 16),
          label: Text(l10n.desktopScheduleAdd),
        ),
      ],
    );
  }
}

class _ScheduleDraft {
  _ScheduleDraft({
    required this.key,
    required this.id,
    required String name,
    required this.enabled,
    required List<String> weekdays,
    required String start,
    required String end,
  }) : name = TextEditingController(text: name),
       start = TextEditingController(text: start),
       end = TextEditingController(text: end),
       weekdays = [...weekdays];

  factory _ScheduleDraft.from(DesktopSchedule row, int key) => _ScheduleDraft(
    key: key,
    id: row.id,
    name: row.name,
    enabled: row.enabled,
    weekdays: row.weekdays,
    start: row.start,
    end: row.end,
  );

  final int key;
  final String id;
  final TextEditingController name;
  final TextEditingController start;
  final TextEditingController end;
  bool enabled;
  final List<String> weekdays;

  void dispose() {
    name.dispose();
    start.dispose();
    end.dispose();
  }

  DesktopSchedule export() => DesktopSchedule(
    id: id,
    name: name.text.trim(),
    enabled: enabled,
    weekdays: [
      for (final day in desktopWeekdays)
        if (weekdays.contains(day)) day,
    ],
    start: start.text.trim(),
    end: end.text.trim(),
  );
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    super.key,
    required this.draft,
    required this.disabled,
    required this.onChanged,
    required this.onStructureChanged,
    required this.onDelete,
  });

  final _ScheduleDraft draft;
  final bool disabled;
  final VoidCallback onChanged;
  final VoidCallback onStructureChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: TextFormField(
                  controller: draft.name,
                  enabled: !disabled,
                  decoration: InputDecoration(
                    labelText: l10n.desktopScheduleName,
                  ),
                  style: AppTextStyle.callout.of(context),
                  onChanged: (_) => onChanged(),
                ),
              ),
              DashboardSwitch(
                value: draft.enabled,
                semanticLabel: l10n.desktopScheduleEnabled,
                onChanged: disabled
                    ? null
                    : (value) {
                        draft.enabled = value;
                        onStructureChanged();
                      },
              ),
              SizedBox(
                height: 32,
                child: DashboardIconButton(
                  glyph: AppGlyphs.delete,
                  tooltip: l10n.desktopScheduleDelete,
                  onPressed: disabled ? null : onDelete,
                ),
              ),
            ],
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: TextFormField(
                  controller: draft.start,
                  enabled: !disabled,
                  decoration: InputDecoration(
                    labelText: l10n.desktopScheduleStart,
                    hintText: '08:00',
                  ),
                  style: AppTextStyle.callout.of(context).toTabular,
                  onChanged: (_) => onChanged(),
                ),
              ),
              Expanded(
                child: TextFormField(
                  controller: draft.end,
                  enabled: !disabled,
                  decoration: InputDecoration(
                    labelText: l10n.desktopScheduleEnd,
                    helperText: l10n.desktopScheduleEndHelper,
                    hintText: '18:00',
                  ),
                  style: AppTextStyle.callout.of(context).toTabular,
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.desktopScheduleWeekdays,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context),
                ),
              ),
              TextButton(
                onPressed: disabled
                    ? null
                    : () {
                        draft.weekdays.clear();
                        onStructureChanged();
                      },
                child: Text(l10n.desktopScheduleEveryDay),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final day in desktopWeekdays)
                _WeekdayChip(
                  label: desktopWeekdayLabel(context, day),
                  selected: draft.weekdays.contains(day),
                  color: colorScheme,
                  onPressed: disabled
                      ? null
                      : () {
                          if (!draft.weekdays.remove(day)) {
                            draft.weekdays.add(day);
                          }
                          onStructureChanged();
                        },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekdayChip extends StatelessWidget {
  const _WeekdayChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final ColorScheme color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return CommonCard(
      isSelected: selected,
      fillsSelection: true,
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        label,
        style: AppTextStyle.caption1
            .of(context, emphasized: true)
            .copyWith(color: selected ? color.onPrimary : null),
      ),
    );
  }
}

String desktopWeekdayLabel(BuildContext context, String key) {
  final l10n = context.l10n;
  return switch (key) {
    'mon' => l10n.desktopWeekdayMon,
    'tue' => l10n.desktopWeekdayTue,
    'wed' => l10n.desktopWeekdayWed,
    'thu' => l10n.desktopWeekdayThu,
    'fri' => l10n.desktopWeekdayFri,
    'sat' => l10n.desktopWeekdaySat,
    _ => l10n.desktopWeekdaySun,
  };
}
