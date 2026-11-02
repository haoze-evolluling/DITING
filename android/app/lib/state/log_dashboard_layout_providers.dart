/// Log dashboard card layout: one stored order per log mode, plus the edit-mode switch.
library;

import 'package:diting_android/data/log_dashboard_widgets.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/hub_settings_providers.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cards a log mode can show, in the order a fresh install shows them. A card outside this list
/// has no data in that mode (the traffic monitor is meaningless when only blocks are logged), so
/// the add sheet never offers it there.
///
/// Order follows what a user opens the page for: the headline figures, then what just happened,
/// then why it was blocked, then usage, and the resolver internals (cache, race, bootstrap) last.
/// The off mode leads with why the page is empty and whether resolving is still healthy.
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

/// Stored layout of one log mode. Holds the AI card even without an API key so adding a key
/// brings it back in place; [visibleLogDashboardWidgetsProvider] does the filtering.
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
    // Unknown names, and cards this mode no longer offers, are skipped.
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

  /// Moves a card within [visible], the list the board shows. [newIndex] is already adjusted,
  /// as [ReorderableListView.onReorderItem] passes it. Hidden cards (the AI card without a key)
  /// keep their stored slots, so a reorder never loses them.
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

  /// An emptied board is a real choice, so it is written as `[]`.
  void _commit(List<LogDashboardWidget> next) {
    state = next;
    ref.read(legacySettingsProvider).setLogDashboardWidgetOrder(
      mode.storageValue,
      [for (final widget in next) widget.name],
    );
  }
}

/// Cards that can render right now: the AI card needs a configured API key.
final visibleLogDashboardWidgetsProvider =
    Provider.family<List<LogDashboardWidget>, LegacyLogMode>((ref, mode) {
      final showAi = ref.watch(agentKeyConfiguredProvider);
      return [
        for (final widget in ref.watch(logDashboardWidgetsProvider(mode)))
          if (showAi || widget != LogDashboardWidget.aiInsight) widget,
      ];
    });

/// Edit mode of the log dashboard; separate from home's so editing one board does not flip the
/// other. Auto-disposed, so leaving the page ends editing.
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
