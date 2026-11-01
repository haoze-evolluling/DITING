/// Which dashboard cards exist, in what order, and whether the board is in edit mode.
///
/// Split out of `dashboard_providers.dart` because this half is pure preference state: the desktop
/// home reads the same stored layout without pulling in the VPN/traffic providers next door.
library;

import 'package:diting/data/dashboard_models.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

LegacySettings _settings(Ref ref) => ref.read(legacySettingsProvider);

/// Dashboard card layout (add, remove, reorder in edit mode), persisted by `DashboardWidget.name`
/// so an app upgrade keeps the board while an unknown name is simply skipped.
final dashboardWidgetsProvider =
    NotifierProvider<DashboardWidgetsNotifier, List<DashboardWidget>>(
      DashboardWidgetsNotifier.new,
    );

class DashboardWidgetsNotifier extends Notifier<List<DashboardWidget>> {
  /// Bumped whenever a card moves from a fixed home block onto the board; an older stored order
  /// gets the new cards inserted once, so an upgrade does not silently lose them.
  static const layoutVersion = 1;

  @override
  List<DashboardWidget> build() {
    final settings = _settings(ref);
    final stored = settings.dashboardWidgetOrder;
    if (stored == null) {
      return defaultDashboardWidgets;
    }
    final byName = {
      for (final widget in DashboardWidget.values) widget.name: widget,
    };
    // Unknown names (a card removed in a later version) are skipped, not restored.
    final layout = [for (final name in stored) ?byName[name]];
    if (settings.dashboardWidgetLayoutVersion >= layoutVersion) {
      return layout;
    }
    // Cards that used to be fixed blocks go to the top of the board, right under the power
    // button, where the user is used to finding them; a board the user emptied on purpose keeps
    // staying empty.
    final missing = [
      for (final widget in const [
        DashboardWidget.provider,
        DashboardWidget.resolution,
      ])
        if (!layout.contains(widget)) widget,
    ];
    final migrated = [...missing, ...layout];
    // Store only: `state` is assigned by this build's return value.
    _write(settings, migrated);
    return migrated;
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
    settings.setDashboardWidgetLayoutVersion(layoutVersion);
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
