/// Notification detail items: which request counts (and the speed readout) the running service
/// shows under its status line, in the user's order. Stored in `notification_settings_prefs`
/// (`stats_items`) and read natively by `NotificationStatsLine`.
library;

import 'dart:convert';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum NotificationStatItem {
  total('total', AppGlyphs.requests),
  passed('passed', AppGlyphs.checkCircle),
  filtered('filtered', AppGlyphs.filter),
  failed('failed', AppGlyphs.error),
  cached('cached', AppGlyphs.layers),
  rewritten('rewritten', AppGlyphs.sliders),
  speed('speed', AppGlyphs.speed);

  const NotificationStatItem(this.id, this.glyph);

  /// Native id; renaming one silently drops it from the notification.
  final String id;
  final Glyph glyph;

  static NotificationStatItem? fromId(String id) {
    for (final item in values) {
      if (item.id == id) return item;
    }
    return null;
  }

  String label(AppL10n l10n) => switch (this) {
    NotificationStatItem.total => l10n.notificationStatTotal,
    NotificationStatItem.passed => l10n.logPassed,
    NotificationStatItem.filtered => l10n.logFiltered,
    NotificationStatItem.failed => l10n.commonFailed,
    NotificationStatItem.cached => l10n.logCacheHits,
    NotificationStatItem.rewritten => l10n.commonRewrite,
    NotificationStatItem.speed => l10n.notificationStatSpeed,
  };

  String description(AppL10n l10n) => switch (this) {
    NotificationStatItem.total => l10n.notificationStatTotalSubtitle,
    NotificationStatItem.passed => l10n.notificationStatPassedSubtitle,
    NotificationStatItem.filtered => l10n.notificationStatFilteredSubtitle,
    NotificationStatItem.failed => l10n.notificationStatFailedSubtitle,
    NotificationStatItem.cached => l10n.notificationStatCachedSubtitle,
    NotificationStatItem.rewritten => l10n.notificationStatRewrittenSubtitle,
    NotificationStatItem.speed => l10n.notificationShowSpeedSubtitle,
  };
}

/// The enabled items, in display order.
class NotificationStatsNotifier extends Notifier<List<NotificationStatItem>> {
  @override
  List<NotificationStatItem> build() {
    final ids = ref.read(legacySettingsProvider).notificationStatsItems;
    return [for (final id in ids) ?NotificationStatItem.fromId(id)];
  }

  void toggle(NotificationStatItem item) {
    final next = [...state];
    if (!next.remove(item)) next.add(item);
    state = next;
    _save();
  }

  /// [newIndex] is already adjusted, as `ReorderableListView.onReorderItem` passes it.
  void move(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= state.length ||
        newIndex < 0 ||
        newIndex >= state.length ||
        oldIndex == newIndex) {
      return;
    }
    final next = [...state];
    next.insert(newIndex, next.removeAt(oldIndex));
    state = next;
    _save();
  }

  void _save() {
    final settings = ref.read(legacySettingsProvider);
    settings.setNotificationStatsItems([for (final item in state) item.id]);
    writeNotificationStatLabels(settings, currentL10n);
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }
}

/// Stores the labels in the current language for the native notification. Written whenever the
/// items change and when the page opens, so a language switch is picked up on the next visit.
void writeNotificationStatLabels(LegacySettings settings, AppL10n l10n) {
  settings.setNotificationStatsLabelsJson(
    jsonEncode({
      for (final item in NotificationStatItem.values)
        if (item != NotificationStatItem.speed) item.id: item.label(l10n),
    }),
  );
}

final notificationStatsProvider =
    NotifierProvider<NotificationStatsNotifier, List<NotificationStatItem>>(
      NotificationStatsNotifier.new,
    );
