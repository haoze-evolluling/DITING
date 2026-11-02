import 'package:diting_android/app/upgrade_resets.dart';
import 'package:diting_android/data/log_dashboard_widgets.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/log_dashboard_layout_providers.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _ui = LegacySettings.uiContainer;

void main() {
  late MemoryLegacyPrefsStore store;
  setUp(() => store = MemoryLegacyPrefsStore());

  UpgradeReset reset(String id, String key) =>
      UpgradeReset.prefs(id: id, since: '9.9.9', container: _ui, keys: [key]);

  group('升级重置体系', () {
    test('每个重置只执行一次，之后写入的值保留', () {
      store.putString(_ui, 'a', 'old');
      expect(runUpgradeResets(store, [reset('r1', 'a')]), ['r1']);
      expect(store.read(_ui, 'a'), isNull);
      store.putString(_ui, 'a', 'new');
      expect(runUpgradeResets(store, [reset('r1', 'a')]), isEmpty);
      expect(store.read(_ui, 'a'), 'new');
    });

    test('新加入的重置只执行新的那一个', () {
      runUpgradeResets(store, [reset('r1', 'a')]);
      store
        ..putString(_ui, 'a', 'kept')
        ..putString(_ui, 'b', 'old');
      expect(runUpgradeResets(store, [reset('r1', 'a'), reset('r2', 'b')]), [
        'r2',
      ]);
      expect(store.read(_ui, 'a'), 'kept');
      expect(store.read(_ui, 'b'), isNull);
    });

    test('失败的重置不记录，下次启动重试，也不影响其它重置', () {
      final failing = UpgradeReset(
        id: 'bad',
        since: '9.9.9',
        apply: (_) => throw StateError('boom'),
      );
      store.putString(_ui, 'a', 'old');
      expect(runUpgradeResets(store, [failing, reset('r1', 'a')]), ['r1']);
      expect(store.read(_ui, 'a'), isNull);
      var calls = 0;
      runUpgradeResets(store, [
        UpgradeReset(id: 'bad', since: '9.9.9', apply: (_) => calls++),
      ]);
      expect(calls, 1);
    });
  });

  test('2.2.1 升级把每个日志模式已保存的布局恢复为默认顺序', () {
    for (final mode in LegacyLogMode.values) {
      store.putString(
        _ui,
        logDashboardWidgetOrderKey(mode.storageValue),
        '["hero"]',
      );
    }
    runUpgradeResets(store, upgradeResets);
    final container = ProviderContainer(
      overrides: [legacyPrefsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    for (final mode in LegacyLogMode.values) {
      expect(
        container.read(logDashboardWidgetsProvider(mode)),
        logDashboardCatalogOf(mode),
      );
    }
    // An edit after the upgrade survives the next launch.
    container
        .read(logDashboardWidgetsProvider(LegacyLogMode.all).notifier)
        .remove(LogDashboardWidget.hero);
    runUpgradeResets(store, upgradeResets);
    expect(
      LegacySettings(store)
          .logDashboardWidgetOrder(LegacyLogMode.all.storageValue),
      isNot(contains('hero')),
    );
  });
}
