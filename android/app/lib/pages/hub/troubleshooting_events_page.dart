/// 故障排查 → 运行事件: the always-on structured timeline, with level/module filters and an export
/// of exactly what is shown. The black box itself is native (`RuntimeEventLog`); this page only
/// reads the tail and lets the user narrow it down.
library;

import 'package:diting_android/data/native/runtime_event.dart';
import 'package:diting_android/state/runtime_event_providers.dart';
import 'package:diting_android/state/runtime_log_providers.dart';
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
    final filtered = events.where((event) {
      if (_level == _LevelFilter.warnPlus && !event.isWarnOrAbove) return false;
      if (_level == _LevelFilter.errorOnly && !event.isError) return false;
      if (_module != null && event.module != _module) return false;
      return true;
    }).toList(growable: false);

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
          onPressed: filtered.isEmpty || _busy
              ? null
              : () => _export(filtered),
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
            if (summary.hasAnomaly)
              CommonCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  spacing: 10,
                  children: [
                    GlyphIcon(
                      AppGlyphs.logs,
                      size: 20,
                      color: colorScheme.error,
                    ),
                    Expanded(
                      child: Text(
                        l10n.troubleshootEventsAnomaly(summary.anomalyCount),
                        style: AppTextStyle.footnote.of(context).copyWith(
                          color: colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            _FilterRow(
              label: l10n.troubleshootEventsLevel,
              choices: [
                MapEntry(l10n.troubleshootEventsAll, _LevelFilter.all),
                MapEntry(l10n.troubleshootEventsWarnPlus, _LevelFilter.warnPlus),
                MapEntry(l10n.troubleshootEventsErrorOnly, _LevelFilter.errorOnly),
              ],
              selected: _level,
              onSelected: (value) => setState(() => _level = value),
            ),
            if (modules.length > 1)
              _FilterRow<String?>(
                label: l10n.troubleshootEventsModule,
                choices: [
                  MapEntry<String, String?>(
                    l10n.troubleshootEventsModuleAll,
                    null,
                  ),
                  for (final module in modules)
                    MapEntry<String, String?>(module, module),
                ],
                selected: _module,
                onSelected: (value) => setState(() => _module = value),
              ),
            generateSection(
              title: l10n.troubleshootEventsTitle,
              items: [
                for (final event in filtered.reversed) _EventRow(event: event),
              ],
              footer: l10n.troubleshootEventsCount(filtered.length),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _FilterRow<T> extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.choices,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final List<MapEntry<String, T>> choices;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SectionBlock(
      title: label,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          spacing: 8,
          children: [
            for (final choice in choices)
              ChoiceChip(
                label: Text(choice.key),
                selected: choice.value == selected,
                onSelected: (_) => onSelected(choice.value),
              ),
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
    final color = event.isError
        ? colorScheme.error
        : event.levelTag >= 2
        ? colorScheme.warning
        : colorScheme.onSurfaceVariant;
    return ListItem(
      leading: GlyphIcon(AppGlyphs.logs, size: 18, color: color),
      title: Text(
        '${event.levelName} · ${event.module}',
        style: AppTextStyle.footnote.of(context).copyWith(color: color),
      ),
      subtitle: Text(
        event.detail.isEmpty ? event.code : '${event.code}  ${event.detail}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        event.timeText.length >= 12 ? event.timeText.substring(11) : event.timeText,
        style: AppTextStyle.caption2.of(context).copyWith(
          color: colorScheme.onSurfaceVariant,
          fontFeatures: appTabularFigures,
        ),
      ),
    );
  }
}
