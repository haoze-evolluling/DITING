/// The built-in app and site blocking card: search, group filters, one tile per service with its
/// plan state and rules, and the per-service weekly plan dialog.
///
/// The old desktop console's `ServicesPanel.vue` is the blueprint. Every toggle posts the selection
/// and adopts the whole state the service answers with, so a rejected change never stays on screen.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_services_models.dart';
import 'package:diting_desktop/data/api/desktop_services_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/service_schedule_dialog.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_desktop/widgets/desktop_picker.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// One compact tile carries a name, its rule count and three controls. Narrower than this the
/// controls no longer fit beside the name, so the tile stacks them under it; narrower still and the
/// switch itself clips, so the grid drops a column instead.
const double _minTileWidth = 232;
const double _wideTileWidth = 320;
const double _tileGap = 8;
const int _maxColumns = 5;

class BlockedServicesCard extends ConsumerStatefulWidget {
  const BlockedServicesCard({super.key});

  @override
  ConsumerState<BlockedServicesCard> createState() =>
      _BlockedServicesCardState();
}

class _BlockedServicesCardState extends ConsumerState<BlockedServicesCard> {
  final _search = TextEditingController();
  String _group = '';
  String _expanded = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _toggleService(DesktopBlockedService service, bool blocked) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopServicesProvider.notifier)
        .toggleService(service.id, blocked);
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (blocked
                ? l10n.desktopServicesBlocked(service.name)
                : l10n.desktopServicesUnblocked(service.name))
          : l10n.desktopServicesActionFailed(error.message),
    );
  }

  Future<void> _editSchedule(DesktopBlockedService service) async {
    final l10n = context.l10n;
    final data = ref.read(desktopServicesProvider).data;
    if (data == null) return;
    final rows = await showServiceScheduleDialog(
      context,
      service: service,
      schedules: data.schedulesOf(service.id),
    );
    if (rows == null || !mounted) return;
    final error = await ref
        .read(desktopServicesProvider.notifier)
        .saveSchedules(service.id, rows);
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (rows.isEmpty
                ? l10n.desktopServicesScheduleRemoved(service.name)
                : l10n.desktopServicesScheduleSaved(service.name))
          : l10n.desktopServicesActionFailed(error.message),
    );
  }

  List<DesktopBlockedService> _filtered(DesktopBlockedServices data) {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final service in data.services)
        if ((_group.isEmpty || service.group == _group) &&
            (query.isEmpty ||
                service.name.toLowerCase().contains(query) ||
                service.id.toLowerCase().contains(query) ||
                service.rules.any((rule) => rule.toLowerCase().contains(query))))
          service,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(desktopServicesProvider);
    final data = state.data;
    final saving = state.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopServicesTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.appsList,
            title: l10n.desktopServicesTitle,
            leading: [
              if (data != null)
                DashboardChip(
                  label: l10n.desktopServicesCount(
                    data.blockedCount,
                    data.services.length,
                  ),
                ),
            ],
            trailing: [
              if (saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopServicesBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          if (data == null)
            _Unavailable(
              loading: state.isLoading,
              error: state.error,
              onRetry: ref.read(desktopServicesProvider.notifier).reload,
            )
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: l10n.desktopServicesSearchHint,
                      prefixIcon: const GlyphIcon(AppGlyphs.search, size: 16),
                    ),
                    style: AppTextStyle.callout.of(context),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                DesktopPicker(
                  glyph: AppGlyphs.filter,
                  semanticLabel: l10n.desktopServicesGroupFilter,
                  label: _group.isEmpty
                      ? l10n.desktopServicesAllGroups
                      : data.groupName(_group),
                  active: _group.isNotEmpty,
                  items: [
                    CommonPopupMenuItem(
                      label: l10n.desktopServicesAllGroups,
                      checked: _group.isEmpty,
                      onPressed: () => setState(() => _group = ''),
                    ),
                    for (final group in data.groups)
                      CommonPopupMenuItem(
                        label: l10n.desktopServicesGroupItem(
                          group.name,
                          group.count,
                        ),
                        checked: _group == group.id,
                        onPressed: () => setState(() => _group = group.id),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _grid(context, data, saving),
          ],
        ],
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    DesktopBlockedServices data,
    bool saving,
  ) {
    final l10n = context.l10n;
    final filtered = _filtered(data);
    if (filtered.isEmpty) {
      return DashboardBlock(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          spacing: 6,
          children: [
            GlyphIcon(
              AppGlyphs.search,
              size: 26,
              color: context.colorScheme.onSurfaceVariant,
            ),
            Text(
              data.services.isEmpty
                  ? l10n.desktopServicesEmpty
                  : l10n.desktopServicesNoMatch,
              textAlign: TextAlign.center,
              style: DashboardText.label(context),
            ),
          ],
        ),
      );
    }
    final expanded = filtered.where((item) => item.id == _expanded);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsOf(constraints.maxWidth);
        final tileWidth =
            (constraints.maxWidth - _tileGap * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: _tileGap,
          children: [
            for (var index = 0; index < filtered.length; index += columns)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: _tileGap,
                  children: [
                    for (var column = 0; column < columns; column++)
                      Expanded(
                        child: index + column < filtered.length
                            ? _tile(
                                filtered[index + column],
                                data: data,
                                saving: saving,
                                wide: tileWidth >= _wideTileWidth,
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            // The rules of the opened tile are long lines, not tile content: they get the full
            // width under the grid instead of widening one tile in the middle of a run.
            if (expanded.isNotEmpty)
              _RulesPanel(
                service: expanded.first,
                data: data,
                onClose: () => setState(() => _expanded = ''),
              ),
          ],
        );
      },
    );
  }

  /// As many equal columns as the card fits, so one row shows several services at once.
  int _columnsOf(double width) {
    final fit = ((width + _tileGap) / (_minTileWidth + _tileGap)).floor();
    if (fit < 1) return 1;
    return fit > _maxColumns ? _maxColumns : fit;
  }

  Widget _tile(
    DesktopBlockedService service, {
    required DesktopBlockedServices data,
    required bool saving,
    required bool wide,
  }) => _ServiceTile(
    service: service,
    data: data,
    saving: saving,
    wide: wide,
    expanded: _expanded == service.id,
    onToggle: (value) => unawaited(_toggleService(service, value)),
    onSchedule: () => unawaited(_editSchedule(service)),
    onExpand: () => setState(
      () => _expanded = _expanded == service.id ? '' : service.id,
    ),
  );
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.data,
    required this.saving,
    required this.wide,
    required this.expanded,
    required this.onToggle,
    required this.onSchedule,
    required this.onExpand,
  });

  final DesktopBlockedService service;
  final DesktopBlockedServices data;
  final bool saving;

  /// True when the tile is wide enough to keep its controls beside the name instead of under it.
  final bool wide;
  final bool expanded;
  final ValueChanged<bool> onToggle;
  final VoidCallback onSchedule;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final blocked = data.isBlocked(service);
    final byGroup = data.blockedByGroup(service);
    final schedule = data.stateOf(service.id);
    final hasSchedule = schedule?.hasSchedule ?? false;
    final info = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          service.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.rowTitle(context),
        ),
        Wrap(
          spacing: 5,
          runSpacing: 3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              l10n.desktopServicesRuleCount(
                data.groupName(service.group),
                service.ruleCount,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(context),
            ),
            if (byGroup)
              DashboardChip(
                label: l10n.desktopServicesByGroup,
                tone: DashboardChipTone.warn,
              ),
            if (hasSchedule)
              DashboardChip(
                label: schedule?.active == true
                    ? l10n.desktopServicesScheduleInside
                    : l10n.desktopServicesScheduleOutside,
                tone: schedule?.active == true
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
              ),
          ],
        ),
      ],
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        SizedBox(
          height: 26,
          child: DashboardIconButton(
            glyph: AppGlyphs.clock,
            tooltip: l10n.desktopServicesScheduleEdit,
            size: 26,
            glyphSize: 14,
            onPressed: saving ? null : onSchedule,
          ),
        ),
        DashboardSwitch(
          value: blocked,
          semanticLabel: service.name,
          onChanged: saving || byGroup ? null : onToggle,
        ),
        SizedBox(
          height: 26,
          child: DashboardIconButton(
            glyph: expanded ? AppGlyphs.eyeOff : AppGlyphs.eye,
            tooltip: l10n.desktopServicesShowRules,
            size: 26,
            glyphSize: 14,
            onPressed: onExpand,
          ),
        ),
      ],
    );
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: wide
          ? Row(
              spacing: 6,
              children: [Expanded(child: info), controls],
            )
          // The run stretches every tile to its tallest neighbour, so the controls of a row stay
          // on one line even when one tile needs a second line for its chips.
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [info, const Spacer(), controls],
            ),
    );
  }
}

/// The rules of the tile whose eye is on: full width under the grid, one rule per line.
class _RulesPanel extends StatelessWidget {
  const _RulesPanel({
    required this.service,
    required this.data,
    required this.onClose,
  });

  final DesktopBlockedService service;
  final DesktopBlockedServices data;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return DashboardBlock(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 2,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      service.name,
                      style: DashboardText.rowTitle(context),
                    ),
                    Text(
                      l10n.desktopServicesRuleCount(
                        data.groupName(service.group),
                        service.ruleCount,
                      ),
                      style: DashboardText.label(context),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 28,
                child: DashboardIconButton(
                  glyph: AppGlyphs.eyeOff,
                  tooltip: l10n.desktopServicesShowRules,
                  size: 28,
                  glyphSize: 15,
                  onPressed: onClose,
                ),
              ),
            ],
          ),
          for (final rule in service.rules)
            Text(
              rule,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1
                  .of(context)
                  .toTabular
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final DesktopApiException? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CommonCircleLoading(size: 22)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(
          l10n.desktopServicesLoadFailed,
          style: DashboardText.label(context),
        ),
        Text(
          error?.message ?? '',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.label(context),
        ),
        FilledButton.tonal(
          onPressed: onRetry,
          child: Text(l10n.desktopRetry),
        ),
      ],
    );
  }
}
