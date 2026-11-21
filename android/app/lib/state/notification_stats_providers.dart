library;

import 'dart:convert';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum NotificationStatItem {
  total('total', TablerIcons.clock),
  passed('passed', TablerIcons.circle_check),
  filtered('filtered', TablerIcons.filter),
  failed('failed', TablerIcons.alert_circle),
  cached('cached', TablerIcons.database),
  rewritten('rewritten', TablerIcons.adjustments),
  speed('speed', TablerIcons.gauge);

  const NotificationStatItem(this.id, this.glyph);

  final String id;
  final IconData glyph;

  static NotificationStatItem? fromId(String id) =>
      values.where((item) => item.id == id).firstOrNull;

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
