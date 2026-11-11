/// Which server-mode dashboard cards exist, in what order, and whether the board is in edit mode.
///
/// Mirrors `dashboard_layout_providers.dart` so the server home behaves like the normal/express
/// home: add, remove and reorder are persisted, while edit mode itself is session-only.
library;

import 'package:diting_android/data/server_dashboard_widgets.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

LegacySettings _settings(Ref ref) => ref.read(legacySettingsProvider);

final serverDashboardWidgetsProvider =
    NotifierProvider<
      ServerDashboardWidgetsNotifier,
      List<ServerDashboardWidget>
    >(ServerDashboardWidgetsNotifier.new);

class ServerDashboardWidgetsNotifier
    extends Notifier<List<ServerDashboardWidget>> {
  @override
  List<ServerDashboardWidget> build() {
    final stored = _settings(ref).serverDashboardWidgetOrder;
    // Null means never edited: use the built-in defaults. An explicit `[]` is a real choice and
    // must stay empty, so it is returned as-is.
    if (stored == null) {
      return defaultServerDashboardWidgets;
    }
    final byName = {
      for (final widget in ServerDashboardWidget.values) widget.name: widget,
    };
    // Unknown names (a card removed in a later version) are skipped, not restored.
    return [for (final name in stored) ?byName[name]];
  }

  void add(ServerDashboardWidget widget) {
    if (state.contains(widget)) {
      return;
    }
    _commit([...state, widget]);
  }

  void remove(ServerDashboardWidget widget) {
    _commit(state.where((item) => item != widget).toList());
  }

  void toggle(ServerDashboardWidget widget) {
    state.contains(widget) ? remove(widget) : add(widget);
  }

  /// `ReorderableListView.onReorderItem`'s `newIndex` is already adjusted, so insert as-is.
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

  void reset() => _commit(defaultServerDashboardWidgets);

  List<ServerDashboardWidget> get available => [
    for (final widget in ServerDashboardWidget.values)
      if (!state.contains(widget)) widget,
  ];

  void _commit(List<ServerDashboardWidget> next) {
    state = next;
    _settings(
      ref,
    ).setServerDashboardWidgetOrder([for (final widget in next) widget.name]);
  }
}

/// Edit mode switch; not persisted, leaving the page ends editing. Kept separate from the normal
/// dashboard's flag so switching work mode never carries an open editor across.
final serverDashboardEditingProvider =
    NotifierProvider<ServerDashboardEditingNotifier, bool>(
      ServerDashboardEditingNotifier.new,
    );

class ServerDashboardEditingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void enter() => state = true;

  void exit() => state = false;

  void toggle() => state = !state;
}
