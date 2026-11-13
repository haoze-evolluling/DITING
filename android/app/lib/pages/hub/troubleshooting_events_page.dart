/// 故障排查 → 运行事件: the always-on structured timeline, with level/module filters and an export
/// of exactly what is shown. The black box itself is native (`RuntimeEventLog`); this page only
/// reads the tail and lets the user narrow it down.
library;

import 'package:diting_android/data/native/runtime_event.dart';
import 'package:diting_android/state/runtime_event_providers.dart';
import 'package:diting_android/state/runtime_log_providers.dart';
import 'package:diting_android/widgets/chip_row.dart';
import 'package:diting_android/widgets/notice.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

enum _LevelFilter { all, warnPlus, errorOnly }

class TroubleshootingEventsPage extends ConsumerStatefulWidget {
  const TroubleshootingEventsPage({super.key});

  @override
  ConsumerState<TroubleshootingEventsPage> createState() =>
      _TroubleshootingEventsPageState();
}

class _TroubleshootingEventsPageState
    extends ConsumerState<TroubleshootingEventsPage> {
  _LevelFilter _level = _LevelFilter.all;
  String? _module;
  bool _busy = false;

  Future<void> _refresh() async {
    ref.invalidate(runtimeEventsProvider);
    await ref.read(runtimeEventsProvider.future);
  }

  Future<void> _export(List<RuntimeEvent> filtered) async {
    if (_busy || filtered.isEmpty) return;
    setState(() => _busy = true);
    final shared = await ref
        .read(runtimeLogBridgeProvider)
        .shareText(
          text: filtered.map((event) => event.raw).join('\n'),
          name: 'runtime-events.txt',
        );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          shared
              ? context.l10n.troubleshootLogsShared
              : context.l10n.troubleshootLogsShareFailed,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final asyncEvents = ref.watch(runtimeEventsProvider);
    final events = asyncEvents.value ?? const <RuntimeEvent>[];
    final summary = RuntimeEventSummary(events);
    final modules = (<String>{for (final event in events) event.module}.toList()
      ..sort());
    final filtered = events
        .where((event) {
          if (_level == _LevelFilter.warnPlus && !event.isWarnOrAbove) {
            return false;
          }
          if (_level == _LevelFilter.errorOnly && !event.isError) return false;
          if (_module != null && event.module != _module) return false;
          return true;
        })
        .toList(growable: false);
    final rows = [
      for (final event in filtered.reversed) _EventRow(event: event),
    ];

    return CommonScaffold(
      title: l10n.troubleshootEventsTitle,
      menuItems: [
        CommonPopupMenuItem(
          label: l10n.troubleshootLogsRefresh,
          glyph: AppGlyphs.refresh,
          onPressed: _refresh,
        ),
        CommonPopupMenuItem(
          label: l10n.troubleshootEventsExport,
          glyph: AppGlyphs.send,
          onPressed: filtered.isEmpty || _busy ? null : () => _export(filtered),
        ),
      ],
      body: NullStatusSwitcher(
        isLoading: asyncEvents.isLoading && !asyncEvents.hasValue,
        isEmpty: events.isEmpty,
        loadingStatus: NullStatus(
          label: l10n.troubleshootLogsReading,
          illustration: NullStatusIllustration.logs,
        ),
        nullStatus: NullStatus(
          label: l10n.troubleshootEventsEmpty,
          description: l10n.troubleshootEventsEmptyBody,
          illustration: NullStatusIllustration.logs,
        ),
        child: PageBody(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: CommonCard(
                child: StatStrip(
                  stats: [
                    StatItem(
                      label: l10n.troubleshootEventsStatTotal,
                      value: '${summary.count}',
                    ),
                    StatItem(
                      label: l10n.troubleshootEventsWarnPlus,
                      value: '${summary.warnOrAbove}',
                      color: colorScheme.warning,
                    ),
                    StatItem(
                      label: l10n.troubleshootEventsStatError,
                      value: '${summary.errors}',
                      color: colorScheme.error,
                    ),
                  ],
                ),
              ),
            ),
            if (summary.hasAnomaly)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: InlineNotice(
                  message: l10n.troubleshootEventsAnomaly(summary.anomalyCount),
                  glyph: AppGlyphs.warning,
                  color: colorScheme.errorContainer,
                  foregroundColor: colorScheme.onErrorContainer,
                ),
              ),
            _FilterPanel(
              levelLabel: l10n.troubleshootEventsLevel,
              levelChoices: [
                MapEntry(l10n.troubleshootEventsAll, _LevelFilter.all),
                MapEntry(
                  l10n.troubleshootEventsWarnPlus,
                  _LevelFilter.warnPlus,
                ),
                MapEntry(
                  l10n.troubleshootEventsErrorOnly,
                  _LevelFilter.errorOnly,
                ),
              ],
              level: _level,
              onLevel: (value) => setState(() => _level = value),
              moduleLabel: l10n.troubleshootEventsModule,
              moduleChoices: modules.length > 1
                  ? [
                      MapEntry<String, String?>(
                        l10n.troubleshootEventsModuleAll,
                        null,
                      ),
                      for (final module in modules)
                        MapEntry<String, String?>(module, module),
                    ]
                  : null,
              module: _module,
              onModule: (value) => setState(() => _module = value),
            ),
            if (rows.isEmpty) ...[
              ListHeader(title: l10n.troubleshootEventsRecentTitle),
              _NoMatch(message: l10n.troubleshootEventsNoMatch),
              ListFooter(text: l10n.troubleshootEventsCount(0)),
            ] else
              generateSection(
                title: l10n.troubleshootEventsRecentTitle,
                items: rows,
                footer: l10n.troubleshootEventsCount(filtered.length),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// The two chip filters. A caption over each row keeps the page's grouped look while the app-wide
/// [FilterPill] replaces the Material `ChoiceChip` used nowhere else.
class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.levelLabel,
    required this.levelChoices,
    required this.level,
    required this.onLevel,
    required this.moduleLabel,
    required this.moduleChoices,
    required this.module,
    required this.onModule,
  });

  final String levelLabel;
  final List<MapEntry<String, _LevelFilter>> levelChoices;
  final _LevelFilter level;
  final ValueChanged<_LevelFilter> onLevel;

  final String moduleLabel;

  /// `null` when the timeline only has one module, so the second row is hidden.
  final List<MapEntry<String, String?>>? moduleChoices;
  final String? module;
  final ValueChanged<String?> onModule;

  @override
  Widget build(BuildContext context) {
    final moduleChoices = this.moduleChoices;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FilterCaption(levelLabel),
          const SizedBox(height: 8),
          ChipRow(
            children: [
              for (final choice in levelChoices)
                FilterPill(
                  label: choice.key,
                  selected: choice.value == level,
                  onPressed: choice.value == level
                      ? null
                      : () => onLevel(choice.value),
                ),
            ],
          ),
          if (moduleChoices != null) ...[
            const SizedBox(height: 16),
            _FilterCaption(moduleLabel),
            const SizedBox(height: 8),
            ChipRow(
              children: [
                for (final choice in moduleChoices)
                  FilterPill(
                    label: choice.key,
                    selected: choice.value == module,
                    onPressed: choice.value == module
                        ? null
                        : () => onModule(choice.value),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterCaption extends StatelessWidget {
  const _FilterCaption(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: context.listCaptionStyle.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

/// Shown when the filters hide every event: a quiet card rather than a blank stretch of page.
class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: CommonCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 8,
          children: [
            GlyphIcon(
              AppGlyphs.filter,
              size: 18,
              color: context.colorScheme.onSurfaceVariant,
            ),
            Flexible(child: Text(message, style: context.listSubtitleStyle)),
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final RuntimeEvent event;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    // The leading glyph mirrors severity; the time column drops the milliseconds the log line
    // carries but a timeline reader never needs.
    final (glyph, color) = event.isError
        ? (AppGlyphs.error, colorScheme.error)
        : event.isWarnOrAbove
        ? (AppGlyphs.warning, colorScheme.warning)
        : (AppGlyphs.info, colorScheme.onSurfaceVariant);
    final timeText = event.timeText.length >= 19
        ? event.timeText.substring(11, 19)
        : event.timeText;
    return ListItem(
      leading: GlyphIcon(glyph, size: 18, color: color),
      title: Text(
        '${event.levelName} · ${event.module}',
        style: AppTextStyle.footnote
            .of(context)
            .copyWith(
              color: event.isWarnOrAbove ? color : colorScheme.onSurfaceVariant,
              fontWeight: event.isWarnOrAbove ? FontWeight.w600 : null,
            ),
      ),
      subtitle: Text(
        event.detail.isEmpty ? event.code : '${event.code}  ${event.detail}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        timeText,
        style: AppTextStyle.caption2
            .of(context)
            .copyWith(
              color: colorScheme.onSurfaceVariant,
              fontFeatures: appTabularFigures,
            ),
      ),
    );
  }
}
