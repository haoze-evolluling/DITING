/// One client-group draft: name, members, blocking overrides, schedule and the two binding sets.
///
/// The old desktop console's `ClientGroupsCard.vue` group block is the blueprint. The editor is
/// driven entirely by the draft its parent owns: every change emits a new [DesktopClientGroup] and
/// the editor only adopts an incoming value that it did not just emit, so typing is never reset by a
/// re-read.
library;

import 'dart:async';
import 'dart:convert';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_client_groups_models.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_common.dart';
import 'package:diting_desktop/pages/hub/widgets/schedule_editor.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_desktop/widgets/desktop_picker.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// The console's four group-level blocking modes; empty inherits the global one.
const List<String> desktopGroupBlockModes = ['', 'null_ip', 'nxdomain', 'refused'];

class ClientGroupEditor extends StatefulWidget {
  const ClientGroupEditor({
    super.key,
    required this.group,
    required this.ruleLists,
    required this.upstreams,
    required this.disabled,
    required this.onChanged,
    required this.onDelete,
  });

  final DesktopClientGroup group;
  final List<DesktopGroupRuleList> ruleLists;
  final List<DesktopGroupUpstream> upstreams;
  final bool disabled;
  final ValueChanged<DesktopClientGroup> onChanged;
  final VoidCallback onDelete;

  @override
  State<ClientGroupEditor> createState() => _ClientGroupEditorState();
}

class _ClientGroupEditorState extends State<ClientGroupEditor> {
  late final _name = TextEditingController(text: widget.group.name);
  late final _clients = TextEditingController(
    text: widget.group.clients.join('\n'),
  );
  late String _emitted = _key(widget.group);

  static String _key(DesktopClientGroup group) => jsonEncode(group.toJson());

  @override
  void didUpdateWidget(ClientGroupEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_key(widget.group) == _emitted) return;
    _emitted = _key(widget.group);
    _name.text = widget.group.name;
    _clients.text = widget.group.clients.join('\n');
  }

  @override
  void dispose() {
    _name.dispose();
    _clients.dispose();
    super.dispose();
  }

  void _emit(DesktopClientGroup group) {
    _emitted = _key(group);
    widget.onChanged(group);
  }

  List<String> _members() => [
    for (final line in _clients.text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  void _toggleRuleList(String id) {
    final ids = [...widget.group.ruleListIds];
    if (!ids.remove(id)) ids.add(id);
    _emit(widget.group.copyWith(ruleListIds: ids));
  }

  void _toggleUpstream(String id) {
    final ids = [...widget.group.upstreamIds];
    if (!ids.remove(id)) ids.add(id);
    _emit(widget.group.copyWith(upstreamIds: ids));
  }

  Future<void> _confirmDelete() async {
    final l10n = context.l10n;
    final confirmed = await confirmDesktopAction(
      context,
      title: l10n.desktopGroupsDeleteTitle,
      body: l10n.desktopGroupsDeleteBody,
      confirmLabel: l10n.desktopGroupsDelete,
    );
    if (confirmed && mounted) widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final group = widget.group;
    final disabled = widget.disabled;
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _name,
                  enabled: !disabled,
                  decoration: InputDecoration(
                    labelText: l10n.desktopGroupsName,
                  ),
                  style: AppTextStyle.callout.of(context),
                  onChanged: (value) =>
                      _emit(group.copyWith(name: value.trim())),
                ),
              ),
              DashboardSwitch(
                value: group.enabled,
                semanticLabel: l10n.desktopGroupsEnabled,
                onChanged: disabled
                    ? null
                    : (value) => _emit(group.copyWith(enabled: value)),
              ),
              SizedBox(
                height: 28,
                child: DashboardIconButton(
                  glyph: AppGlyphs.delete,
                  tooltip: l10n.desktopGroupsDelete,
                  size: 28,
                  glyphSize: 15,
                  onPressed: disabled ? null : () => unawaited(_confirmDelete()),
                ),
              ),
            ],
          ),
          TextField(
            controller: _clients,
            enabled: !disabled,
            minLines: 2,
            maxLines: 5,
            style: AppTextStyle.callout.of(context).toTabular,
            decoration: InputDecoration(
              labelText: l10n.desktopGroupsMembers,
              hintText: l10n.desktopGroupsMembersHint,
            ),
            onChanged: (_) => _emit(group.copyWith(clients: _members())),
          ),
          Text(
            l10n.desktopGroupsMembersBody,
            style: DashboardText.label(context),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.desktopGroupsBlockMode,
                style: DashboardText.rowTitle(context),
              ),
              DesktopPicker(
                glyph: AppGlyphs.block,
                semanticLabel: l10n.desktopGroupsBlockMode,
                label: desktopGroupBlockModeLabel(context, group.blockMode),
                active: group.blockMode.isNotEmpty,
                items: [
                  for (final mode in desktopGroupBlockModes)
                    CommonPopupMenuItem(
                      label: desktopGroupBlockModeLabel(context, mode),
                      checked: group.blockMode == mode,
                      onPressed: disabled
                          ? null
                          : () => _emit(group.copyWith(blockMode: mode)),
                    ),
                ],
              ),
            ],
          ),
          FilterToggleRow(
            title: l10n.desktopGroupsAllowlistOnly,
            body: l10n.desktopGroupsAllowlistOnlyBody,
            value: group.allowlistOnly,
            onChanged: disabled
                ? null
                : (value) => _emit(group.copyWith(allowlistOnly: value)),
          ),
          FilterToggleRow(
            title: l10n.desktopGroupsSchedule,
            body: l10n.desktopGroupsScheduleBody,
            value: group.scheduleEnabled,
            onChanged: disabled
                ? null
                : (value) => _emit(group.copyWith(scheduleEnabled: value)),
          ),
          if (group.scheduleEnabled)
            ScheduleEditor(
              rows: group.schedules,
              disabled: disabled,
              onChanged: (rows) => _emit(group.copyWith(schedules: rows)),
            ),
          _Bindings(
            title: l10n.desktopGroupsRuleLists,
            inheritLabel: l10n.desktopGroupsInheritAll,
            emptyLabel: l10n.desktopGroupsNoRuleLists,
            inheritNote: l10n.desktopGroupsRuleListsInherited,
            selectedNote: l10n.desktopGroupsRuleListsSelected,
            selected: group.ruleListIds,
            disabled: disabled,
            onInherit: () => _emit(group.copyWith(ruleListIds: const [])),
            options: [
              for (final list in widget.ruleLists)
                (
                  id: list.id,
                  label: list.label,
                  tooltip: list.enabled
                      ? l10n.desktopGroupsListEnabled
                      : l10n.desktopGroupsListDisabled,
                  onPressed: () => _toggleRuleList(list.id),
                ),
            ],
          ),
          _Bindings(
            title: l10n.desktopGroupsUpstreams,
            inheritLabel: l10n.desktopGroupsInheritChain,
            emptyLabel: l10n.desktopGroupsNoUpstreams,
            inheritNote: l10n.desktopGroupsUpstreamsInherited,
            selectedNote: l10n.desktopGroupsUpstreamsSelected,
            selected: group.upstreamIds,
            disabled: disabled,
            onInherit: () => _emit(group.copyWith(upstreamIds: const [])),
            options: [
              for (final upstream in widget.upstreams)
                (
                  id: upstream.id,
                  label: upstream.id,
                  tooltip: '${upstream.protocol} · ${upstream.server}',
                  onPressed: () => _toggleUpstream(upstream.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String desktopGroupBlockModeLabel(BuildContext context, String mode) {
  final l10n = context.l10n;
  return switch (mode) {
    'null_ip' => l10n.desktopGroupsModeNullIp,
    'nxdomain' => l10n.desktopGroupsModeNxdomain,
    'refused' => l10n.desktopGroupsModeRefused,
    _ => l10n.desktopGroupsModeInherit,
  };
}

typedef _BindingOption = ({
  String id,
  String label,
  String tooltip,
  VoidCallback onPressed,
});

class _Bindings extends StatelessWidget {
  const _Bindings({
    required this.title,
    required this.inheritLabel,
    required this.emptyLabel,
    required this.inheritNote,
    required this.selectedNote,
    required this.selected,
    required this.disabled,
    required this.onInherit,
    required this.options,
  });

  final String title;
  final String inheritLabel;
  final String emptyLabel;
  final String inheritNote;
  final String selectedNote;
  final List<String> selected;
  final bool disabled;
  final VoidCallback onInherit;
  final List<_BindingOption> options;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(title, style: DashboardText.rowTitle(context)),
            TextButton(
              onPressed: disabled ? null : onInherit,
              child: Text(inheritLabel),
            ),
          ],
        ),
        if (options.isEmpty)
          Text(emptyLabel, style: DashboardText.label(context))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in options)
                Tooltip(
                  message: option.tooltip,
                  child: CommonCard(
                    isSelected: selected.contains(option.id),
                    fillsSelection: true,
                    onPressed: disabled ? null : option.onPressed,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Text(
                      option.label,
                      style: AppTextStyle.caption1
                          .of(
                            context,
                            emphasized: true,
                          )
                          .copyWith(
                            color: selected.contains(option.id)
                                ? context.colorScheme.onPrimary
                                : null,
                          ),
                    ),
                  ),
                ),
            ],
          ),
        Text(
          selected.isEmpty ? inheritNote : selectedNote,
          style: DashboardText.label(context),
        ),
      ],
    );
  }
}
