library;

import 'package:diting_android/data/dashboard_models.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

LegacySettings _settings(Ref ref) => ref.read(legacySettingsProvider);

bool _isValidMove(int oldIndex, int newIndex, int length) =>
    oldIndex >= 0 &&
    oldIndex < length &&
    newIndex >= 0 &&
    newIndex < length &&
    newIndex != oldIndex;

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
    if (state.contains(widget)) {
      remove(widget);
    } else {
      add(widget);
    }
  }

  void move(int oldIndex, int newIndex) {
    if (!_isValidMove(oldIndex, newIndex, state.length)) {
      return;
    }
    final next = [...state];
    next.insert(newIndex, next.removeAt(oldIndex));
    _commit(next);
  }

  void moveVisible(List<DashboardWidget> visible, int oldIndex, int newIndex) {
    if (!_isValidMove(oldIndex, newIndex, visible.length)) {
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

final dashboardEditingProvider =
    NotifierProvider<DashboardEditingNotifier, bool>(
      DashboardEditingNotifier.new,
    );

class DashboardEditingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void enter() => state = true;

  void toggle() => state = !state;
}
