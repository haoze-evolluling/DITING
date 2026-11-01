/// The `hub` branch's time plan: the switch, the named windows and the service's "active now" state.
///
/// The old desktop console's `SchedulePanel.vue` and `ScheduleEditor.vue` are the blueprint. Windows
/// are a local draft; only the save button posts them, and the page then shows what the service
/// re-reads.
library;

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:diting/desktop/data/api/desktop_schedule_models.dart';
import 'package:diting/desktop/data/api/desktop_schedule_providers.dart';
import 'package:diting/desktop/pages/hub/widgets/schedule_editor.dart';
import 'package:diting/desktop/pages/home/desktop_dashboard.dart';
import 'package:diting/desktop/widgets/desktop_feedback.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const double _contentMaxWidth = 880;

class DesktopSchedulePage extends ConsumerStatefulWidget {
  const DesktopSchedulePage({super.key});

  static const path = '/hub/filter-schedule';

  @override
  ConsumerState<DesktopSchedulePage> createState() => _DesktopSchedulePageState();
}

class _DesktopSchedulePageState extends ConsumerState<DesktopSchedulePage> {
  DesktopScheduleConfig? _adopted;
  List<DesktopSchedule> _rows = const [];
  bool _enabled = false;

  void _adopt(DesktopScheduleConfig config) {
    if (identical(_adopted, config)) return;
    _adopted = config;
    _rows = config.schedules;
    _enabled = config.enabled;
  }

  Future<void> _save(DesktopScheduleConfig config) async {
    final l10n = context.l10n;
    final rows = [
      for (final row in _rows)
        if (row.isComplete) row,
    ];
    final error = await ref
        .read(desktopScheduleProvider.notifier)
        .save(config.copyWith(enabled: _enabled, schedules: rows));
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopScheduleSaved
          : l10n.desktopScheduleSaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(desktopScheduleProvider);
    final config = state.config;
    if (config != null) _adopt(config);
    void retry() => ref.read(desktopScheduleProvider.notifier).reload();
    return CommonScaffold(
      title: l10n.desktopSchedulePageTitle,
      actions: [
        IconButton(
          tooltip: l10n.desktopScheduleRefresh,
          onPressed: state.saving ? null : retry,
          icon: state.isLoading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              : const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: config == null
          ? _Unavailable(
              loading: state.isLoading,
              error: state.error,
              onRetry: retry,
            )
          : PageBody(
              children: [
                state.isStale
                    ? StaleStatusNotice(onRetry: retry)
                    : const SizedBox.shrink(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _contentMaxWidth,
                      ),
                      child: _card(context, config, state),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _card(
    BuildContext context,
    DesktopScheduleConfig config,
    DesktopScheduleState state,
  ) {
    final l10n = context.l10n;
    final enabledCount = _rows.where((row) => row.enabled).length;
    final (label, tone) = !_enabled || enabledCount == 0
        ? (l10n.desktopScheduleBadgeOff, DashboardChipTone.idle)
        : config.active
        ? (l10n.desktopScheduleBadgeActive, DashboardChipTone.ok)
        : (l10n.desktopScheduleBadgePaused, DashboardChipTone.warn);
    return DashboardCard(
      semanticLabel: l10n.desktopScheduleTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.clock,
            title: l10n.desktopScheduleTitle,
            leading: [DashboardChip(label: label, tone: tone, dot: true)],
            trailing: [
              if (state.saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else
                DashboardIconButton(
                  glyph: AppGlyphs.check,
                  tooltip: l10n.desktopScheduleSave,
                  onPressed: () => unawaited(_save(config)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopScheduleBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          DashboardBlock(
            child: Row(
              spacing: 10,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        l10n.desktopScheduleEnable,
                        style: DashboardText.rowTitle(context),
                      ),
                      Text(
                        l10n.desktopScheduleEnableBody,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DashboardText.label(context),
                      ),
                    ],
                  ),
                ),
                DashboardSwitch(
                  value: _enabled,
                  semanticLabel: l10n.desktopScheduleEnable,
                  onChanged: state.saving
                      ? null
                      : (value) => setState(() => _enabled = value),
                ),
              ],
            ),
          ),
          if (_enabled) ...[
            const SizedBox(height: 12),
            ScheduleEditor(
              rows: _rows,
              disabled: state.saving,
              onChanged: (rows) => _rows = rows,
            ),
            if (enabledCount == 0) ...[
              const SizedBox(height: 8),
              Text(
                l10n.desktopScheduleNoEnabled,
                style: DashboardText.label(
                  context,
                  color: context.colorScheme.warning,
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonalIcon(
              onPressed: state.saving
                  ? null
                  : () => unawaited(_save(config)),
              icon: const GlyphIcon(AppGlyphs.check, size: 16),
              label: Text(
                state.saving
                    ? l10n.desktopScheduleSaving
                    : l10n.desktopScheduleSave,
              ),
            ),
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
    if (loading) return const Center(child: CommonCircleLoading.page());
    final unauthorized = error?.unauthorized ?? false;
    return AppBarClearance(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: NullStatus(
            illustration: unauthorized
                ? NullStatusIllustration.permission
                : NullStatusIllustration.error,
            label: l10n.desktopScheduleLoadFailed,
            description: unauthorized
                ? l10n.desktopBackendUnauthorizedBody
                : error?.message,
            action: FilledButton.tonal(
              onPressed: onRetry,
              child: Text(l10n.desktopRetry),
            ),
          ),
        ),
      ),
    );
  }
}
