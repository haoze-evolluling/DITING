library;

import 'package:diting_android/data/log_dashboard_widgets.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/hub_settings_providers.dart';
import 'package:diting_android/state/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

List<LogDashboardWidget> logDashboardCatalogOf(LegacyLogMode mode) =>
    switch (mode) {
      LegacyLogMode.all => const [
        LogDashboardWidget.hero,
        LogDashboardWidget.stats,
        LogDashboardWidget.recentRequests,
        LogDashboardWidget.trafficStructure,
        LogDashboardWidget.ruleBlocks,
        LogDashboardWidget.aiInsight,
        LogDashboardWidget.trafficMonitor,
        LogDashboardWidget.requestOverview,
        LogDashboardWidget.cacheHotspots,
        LogDashboardWidget.raceWinners,
        LogDashboardWidget.bootstrapDns,
      ],
      LegacyLogMode.blockedAndErrors => const [
        LogDashboardWidget.hero,
        LogDashboardWidget.filteredHighlight,
        LogDashboardWidget.recentBlocked,
        LogDashboardWidget.ruleBlocks,
        LogDashboardWidget.trafficStructure,
        LogDashboardWidget.aiInsight,
      ],
      LegacyLogMode.off => const [
        LogDashboardWidget.hero,
        LogDashboardWidget.privacyMode,
        LogDashboardWidget.resolutionPerf,
        LogDashboardWidget.offModeMetric,
        LogDashboardWidget.cacheHotspots,
        LogDashboardWidget.raceWinners,
        LogDashboardWidget.bootstrapDns,
      ],
    };

final logDashboardWidgetsProvider =
    NotifierProvider.family<
      LogDashboardWidgetsNotifier,
      List<LogDashboardWidget>,
      LegacyLogMode
    >(LogDashboardWidgetsNotifier.new);

class LogDashboardWidgetsNotifier extends Notifier<List<LogDashboardWidget>> {
  LogDashboardWidgetsNotifier(this.mode);

  final LegacyLogMode mode;

  @override
  List<LogDashboardWidget> build() {
    final stored = ref
        .read(legacySettingsProvider)
        .logDashboardWidgetOrder(mode.storageValue);
    final catalog = logDashboardCatalogOf(mode);
    if (stored == null) {
      return catalog;
    }
    final byName = {for (final widget in catalog) widget.name: widget};
    return [for (final name in stored) ?byName[name]];
  }

  void add(LogDashboardWidget widget) {
    if (state.contains(widget) ||
        !logDashboardCatalogOf(mode).contains(widget)) {
      return;
    }
    _commit([...state, widget]);
  }

  void remove(LogDashboardWidget widget) {
    _commit(state.where((item) => item != widget).toList());
  }

  void moveVisible(
    List<LogDashboardWidget> visible,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex < 0 || oldIndex >= visible.length) {
      return;
    }
    if (newIndex < 0 || newIndex >= visible.length || newIndex == oldIndex) {
      return;
    }
    final reordered = [...visible];
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    final shown = visible.toSet();
    final pending = reordered.iterator;
    _commit([
      for (final widget in state)
        if (shown.contains(widget)) (pending..moveNext()).current else widget,
    ]);
  }

  void reset() => _commit(logDashboardCatalogOf(mode));

  void _commit(List<LogDashboardWidget> next) {
    state = next;
    ref.read(legacySettingsProvider).setLogDashboardWidgetOrder(
      mode.storageValue,
      [for (final widget in next) widget.name],
    );
  }
}

final visibleLogDashboardWidgetsProvider =
    Provider.family<List<LogDashboardWidget>, LegacyLogMode>((ref, mode) {
      final showAi = ref.watch(agentKeyConfiguredProvider);
      return [
        for (final widget in ref.watch(logDashboardWidgetsProvider(mode)))
          if (showAi || widget != LogDashboardWidget.aiInsight) widget,
      ];
    });

final logDashboardEditingProvider =
    NotifierProvider.autoDispose<LogDashboardEditingNotifier, bool>(
      LogDashboardEditingNotifier.new,
    );

class LogDashboardEditingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void enter() => state = true;

  void toggle() => state = !state;
}
