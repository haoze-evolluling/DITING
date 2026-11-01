/// The client-group card: the master switch, one editor per group and the single save button.
///
/// The old desktop console's `ClientGroupsCard.vue` is the blueprint. The whole configuration is one
/// document: nothing is written until "save", and the service may drop groups without members, so a
/// save adopts the re-read configuration.
library;

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_client_groups_models.dart';
import 'package:diting/desktop/data/api/desktop_client_groups_providers.dart';
import 'package:diting/desktop/pages/hub/widgets/filter_common.dart';
import 'package:diting/desktop/pages/traffic/widgets/client_group_editor.dart';
import 'package:diting/desktop/widgets/desktop_feedback.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ClientGroupsCard extends ConsumerStatefulWidget {
  const ClientGroupsCard({
    super.key,
    required this.data,
    required this.saving,
  });

  final DesktopClientGroups data;
  final bool saving;

  @override
  ConsumerState<ClientGroupsCard> createState() => _ClientGroupsCardState();
}

class _ClientGroupsCardState extends ConsumerState<ClientGroupsCard> {
  late bool _enabled = widget.data.enabled;
  late List<_Draft> _drafts = _wrap(widget.data.groups);
  DesktopClientGroups? _adopted;
  bool _dirty = false;
  int _nextKey = 0;

  /// Stable row keys: deleting a middle group must not move the next group's text into the row
  /// above it, which is exactly what an index key does.
  List<_Draft> _wrap(List<DesktopClientGroup> groups) => [
    for (final group in groups) _Draft(_nextKey++, group),
  ];

  List<DesktopClientGroup> get _groups => [
    for (final draft in _drafts) draft.group,
  ];

  @override
  void initState() {
    super.initState();
    _adopted = widget.data;
  }

  @override
  void didUpdateWidget(ClientGroupsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(_adopted, widget.data)) return;
    _adopted = widget.data;
    if (_dirty) return;
    setState(() {
      _enabled = widget.data.enabled;
      _drafts = _wrap(widget.data.groups);
    });
  }

  void _update(int index, DesktopClientGroup group) {
    setState(() {
      _drafts = [
        for (var i = 0; i < _drafts.length; i++)
          if (i == index) _drafts[i].withGroup(group) else _drafts[i],
      ];
      _dirty = true;
    });
  }

  void _add() {
    setState(() {
      _drafts = [
        ..._drafts,
        _Draft(
          _nextKey++,
          DesktopClientGroup(
            name: context.l10n.desktopGroupsNewName(_drafts.length + 1),
          ),
        ),
      ];
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    // A group without members can never match, and an incomplete window is not a window: the
    // console drops both before it writes.
    final groups = [
      for (final group in _groups)
        if (group.clients.isNotEmpty)
          group.copyWith(
            schedules: group.scheduleEnabled
                ? [
                    for (final row in group.schedules)
                      if (row.isComplete) row,
                  ]
                : const [],
          ),
    ];
    final error = await ref
        .read(desktopClientGroupsProvider.notifier)
        .save(enabled: _enabled, groups: groups);
    if (!mounted) return;
    if (error == null) setState(() => _dirty = false);
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopGroupsSaved
          : l10n.desktopTrafficSaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final data = widget.data;
    final saving = widget.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopGroupsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.layers,
            title: l10n.desktopGroupsTitle,
            trailing: [
              if (saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else
                SizedBox(
                  height: 28,
                  child: DashboardIconButton(
                    glyph: AppGlyphs.check,
                    tooltip: l10n.desktopGroupsSave,
                    size: 28,
                    glyphSize: 15,
                    onPressed: () => unawaited(_save()),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DashboardChip(
                label: _enabled
                    ? l10n.desktopGroupsOn
                    : l10n.desktopGroupsOff,
                tone: _enabled
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
                dot: _enabled,
              ),
              Text(
                l10n.desktopGroupsCount(
                  _groups.where((group) => group.enabled).length,
                  _groups.length,
                ),
                style: DashboardText.label(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopGroupsBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          FilterToggleRow(
            title: l10n.desktopGroupsMaster,
            body: l10n.desktopGroupsMasterBody,
            value: _enabled,
            onChanged: saving
                ? null
                : (value) => setState(() {
                    _enabled = value;
                    _dirty = true;
                  }),
          ),
          if (_enabled) ...[
            const SizedBox(height: 10),
            for (var index = 0; index < _drafts.length; index++) ...[
              ClientGroupEditor(
                key: ValueKey(_drafts[index].key),
                group: _drafts[index].group,
                ruleLists: data.ruleLists,
                upstreams: data.upstreams,
                disabled: saving,
                onChanged: (group) => _update(index, group),
                onDelete: () => setState(() {
                  _drafts = [
                    for (var i = 0; i < _drafts.length; i++)
                      if (i != index) _drafts[i],
                  ];
                  _dirty = true;
                }),
              ),
              const SizedBox(height: 10),
            ],
            TextButton.icon(
              onPressed: saving ? null : _add,
              icon: const GlyphIcon(AppGlyphs.add, size: 15),
              label: Text(l10n.desktopGroupsAdd),
            ),
            if (_drafts.isEmpty)
              Text(
                l10n.desktopGroupsEmpty,
                style: DashboardText.label(context),
              ),
          ],
          const SizedBox(height: 6),
          Text(
            l10n.desktopGroupsFooter,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}

/// A draft row with a key that survives edits and deletions.
class _Draft {
  const _Draft(this.key, this.group);

  final int key;
  final DesktopClientGroup group;

  _Draft withGroup(DesktopClientGroup next) => _Draft(key, next);
}
