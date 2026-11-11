// Launcher icon style: persistence, the native switch call, and launch-time reconcile.

import 'package:diting_android/data/native/launcher_icon_bridge.dart';
import 'package:diting_android/state/launcher_icon_providers.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLauncherIconBridge extends LauncherIconBridge {
  _FakeLauncherIconBridge({
    LauncherIconStyle current = LauncherIconStyle.standard,
  }) : _current = current;

  LauncherIconStyle _current;
  final List<LauncherIconStyle> applied = [];
  bool reject = false;

  @override
  Future<LauncherIconStyle> current() async => _current;

  @override
  Future<bool> apply(LauncherIconStyle style) async {
    applied.add(style);
    if (reject) return false;
    _current = style;
    return true;
  }
}

ProviderContainer _container(
  MemoryLegacyPrefsStore store,
  LauncherIconBridge bridge,
) {
  final container = ProviderContainer(
    overrides: [
      legacyPrefsStoreProvider.overrideWithValue(store),
      launcherIconBridgeProvider.overrideWithValue(bridge),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('默认使用内置图标', () {
    final container = _container(
      MemoryLegacyPrefsStore(),
      _FakeLauncherIconBridge(),
    );
    expect(container.read(launcherIconProvider), LauncherIconStyle.standard);
  });

  test('选择 AdGuard 会持久化并调用原生切换', () async {
    final store = MemoryLegacyPrefsStore();
    final bridge = _FakeLauncherIconBridge();
    final container = _container(store, bridge);

    final applied = await container
        .read(launcherIconProvider.notifier)
        .select(LauncherIconStyle.adguard);

    expect(applied, isTrue);
    expect(store.read('dns_vpn_prefs', 'launcher_icon_style'), 'adguard');
    expect(container.read(launcherIconProvider), LauncherIconStyle.adguard);
    expect(bridge.applied, [LauncherIconStyle.adguard]);
  });

  test('重新打开后仍是上次选择的图标', () async {
    final store = MemoryLegacyPrefsStore();
    await _container(
      store,
      _FakeLauncherIconBridge(),
    ).read(launcherIconProvider.notifier).select(LauncherIconStyle.adguard);

    final reopened = _container(store, _FakeLauncherIconBridge());
    expect(reopened.read(launcherIconProvider), LauncherIconStyle.adguard);
  });

  test('原生拒绝切换时保留选择并返回失败', () async {
    final store = MemoryLegacyPrefsStore();
    final bridge = _FakeLauncherIconBridge()..reject = true;
    final container = _container(store, bridge);

    final applied = await container
        .read(launcherIconProvider.notifier)
        .select(LauncherIconStyle.adguard);

    expect(applied, isFalse);
    expect(store.read('dns_vpn_prefs', 'launcher_icon_style'), 'adguard');
    expect(container.read(launcherIconProvider), LauncherIconStyle.adguard);
  });

  test('启动时仅在平台状态与存储不一致时重新应用', () async {
    final matching = _FakeLauncherIconBridge(current: LauncherIconStyle.adguard);
    await reconcileLauncherIcon(matching, 'adguard');
    expect(matching.applied, isEmpty);

    final stale = _FakeLauncherIconBridge();
    await reconcileLauncherIcon(stale, 'adguard');
    expect(stale.applied, [LauncherIconStyle.adguard]);
  });

  test('未知存储值回退到默认图标', () {
    expect(
      LauncherIconStyle.fromStorageValue('bogus'),
      LauncherIconStyle.standard,
    );
    expect(LauncherIconStyle.fromStorageValue(null), LauncherIconStyle.standard);
  });
}
