/// Which dashboard cards exist, in what order, and whether the board is in edit mode.
///
/// Split out of `dashboard_providers.dart` because this half is pure preference state: the desktop
/// home reads the same stored layout without pulling in the VPN/traffic providers next door.
library;

import 'package:diting_android/data/dashboard_models.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

LegacySettings _settings(Ref ref) => ref.read(legacySettingsProvider);

/// Dashboard card layout (add, remove, reorder in edit mode), persisted by `DashboardWidget.name`
/// so an app upgrade keeps the board while an unknown name is simply skipped.
final dashboardWidgetsProvider =
    NotifierProvider<DashboardWidgetsNotifier, List<DashboardWidget>>(
      DashboardWidgetsNotifier.new,
    );

class DashboardWidgetsNotifier extends Notifier<List<DashboardWidget>> {
  @override
  List<DashboardWidget> build() {
    final stored = _settings(ref).dashboardWidgetOrder;
    if (stored == null) {
      return defaultDashboardWidgets;
    }
    final byName = {
      for (final widget in DashboardWidget.values) widget.name: widget,
    };
    // Unknown names (a card removed in an earlier version) are skipped, not restored.
    return [for (final name in stored) ?byName[name]];
  }

  void add(DashboardWidget widget) {
    if (state.contains(widget)) {
      return;
    }
    _commit([...state, widget]);
  }

  void remove(DashboardWidget widget) {
    _commit(state.where((item) => item != widget).toList());
  }

  void toggle(DashboardWidget widget) {
    state.contains(widget) ? remove(widget) : add(widget);
  }

  /// Moves a card; [ReorderableListView.onReorderItem]'s `newIndex` is already adjusted, so insert
  /// as-is.
  void move(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.length) {
      return;
    }
    if (newIndex < 0 || newIndex >= state.length || newIndex == oldIndex) {
      return;
    }
    final next = [...state];
    next.insert(newIndex, next.removeAt(oldIndex));
    _commit(next);
  }

  /// Moves a card within [visible], the list the board shows. [newIndex] is already adjusted,
  /// as `ReorderableListView.onReorderItem` passes it. Cards hidden by the current mode keep
  /// their stored slots, so a reorder never loses them.
  void moveVisible(List<DashboardWidget> visible, int oldIndex, int newIndex) {
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

  void reset() => _commit(defaultDashboardWidgets);

  List<DashboardWidget> get available => [
    for (final widget in DashboardWidget.values)
      if (!state.contains(widget)) widget,
  ];

  /// Updates the provider and the store together. An emptied board is a real choice, so it is
  /// written as `[]` instead of being removed; only a missing key restores the defaults.
  void _commit(List<DashboardWidget> next) {
    state = next;
    _write(_settings(ref), next);
  }

  static void _write(LegacySettings settings, List<DashboardWidget> layout) {
    settings.setDashboardWidgetOrder([
      for (final widget in layout) widget.name,
    ]);
  }
}

/// Edit mode switch; not persisted, leaving the page ends editing.
final dashboardEditingProvider =
    NotifierProvider<DashboardEditingNotifier, bool>(
      DashboardEditingNotifier.new,
    );

class DashboardEditingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void enter() => state = true;

  void exit() => state = false;

  void toggle() => state = !state;
}
