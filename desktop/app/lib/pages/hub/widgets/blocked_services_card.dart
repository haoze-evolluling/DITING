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

/// Three tiles need this much width; two need the lower one; below that they stack.
const double _threeColumnBreakpoint = 1120;
const double _twoColumnBreakpoint = 720;

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= _threeColumnBreakpoint
            ? 3
            : constraints.maxWidth >= _twoColumnBreakpoint
            ? 2
            : 1;
        final tiles = [
          for (final service in filtered)
            _ServiceTile(
              service: service,
              data: data,
              saving: saving,
              expanded: _expanded == service.id,
              onToggle: (value) =>
                  unawaited(_toggleService(service, value)),
              onSchedule: () => unawaited(_editSchedule(service)),
              onExpand: () => setState(
                () => _expanded = _expanded == service.id ? '' : service.id,
              ),
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            for (var index = 0; index < tiles.length; index += columns)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  for (var column = 0; column < columns; column++)
                    Expanded(
                      child: index + column < tiles.length
                          ? tiles[index + column]
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.data,
    required this.saving,
    required this.expanded,
    required this.onToggle,
    required this.onSchedule,
    required this.onExpand,
  });

  final DesktopBlockedService service;
  final DesktopBlockedServices data;
  final bool saving;
  final bool expanded;
  final ValueChanged<bool> onToggle;
  final VoidCallback onSchedule;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final blocked = data.isBlocked(service);
    final byGroup = data.blockedByGroup(service);
    final schedule = data.stateOf(service.id);
    final hasSchedule = schedule?.hasSchedule ?? false;
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Row(
            spacing: 6,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          service.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DashboardText.rowTitle(context),
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
                    Text(
                      l10n.desktopServicesRuleCount(
                        data.groupName(service.group),
                        service.ruleCount,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardText.label(context),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 28,
                child: DashboardIconButton(
                  glyph: AppGlyphs.clock,
                  tooltip: l10n.desktopServicesScheduleEdit,
                  size: 28,
                  glyphSize: 15,
                  onPressed: saving ? null : onSchedule,
                ),
              ),
              DashboardSwitch(
                value: blocked,
                semanticLabel: service.name,
                onChanged: saving || byGroup ? null : onToggle,
              ),
              SizedBox(
                height: 28,
                child: DashboardIconButton(
                  glyph: expanded
                      ? AppGlyphs.eyeOff
                      : AppGlyphs.eye,
                  tooltip: l10n.desktopServicesShowRules,
                  size: 28,
                  glyphSize: 15,
                  onPressed: onExpand,
                ),
              ),
            ],
          ),
          if (expanded)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 2,
              children: [
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
