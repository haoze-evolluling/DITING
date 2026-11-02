// App picker data and its unsaved-changes guard: inventory, filters, mutual exclusion
// between the four lists, and the dialog that asks before leaving.

import 'package:diting_android/app/app.dart';
import 'package:diting_android/data/native/apps_bridge.dart';
import 'package:diting_android/data/native/permissions_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/router.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_android/state/permission_providers.dart';
import 'package:diting_android/widgets/app_list_error_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_host.dart';
import 'support/test_hooks.dart';

part 'app_picker_test_unsaved.dart';

void main() {
  group('应用名单数据', _appPickerData);
  group('未保存改动确认', _unsavedChanges);
  group('读不到应用列表', _appListErrorState);
}

/// Data behavior of the app-picker pages - inventory, filter, sort, persist, cleanup
void _appPickerData() {
  const systemApp = InstalledApp(
    packageName: 'com.android.systemui',
    label: 'System UI',
    isSystem: true,
    uid: 1000,
  );
  const maps = InstalledApp(
    packageName: 'com.example.maps',
    label: '地图',
    isSystem: false,
    uid: 10101,
  );
  const chat = InstalledApp(
    packageName: 'com.example.chat',
    label: 'Chat',
    isSystem: false,
    uid: 10102,
  );
  const device = [systemApp, maps, chat];

  ProviderContainer containerWith([
    Map<String, Map<String, Object>> seed = const {},
  ]) {
    final container = ProviderContainer(
      overrides: [
        legacyPrefsStoreProvider.overrideWithValue(
          MemoryLegacyPrefsStore({
            for (final entry in seed.entries)
              entry.key: Map<String, Object>.from(entry.value),
          }),
        ),
        installedAppsSourceProvider.overrideWithValue(_FakeAppsSource(device)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('installedAppsProvider', () {
    test('读通道后按标签升序给出一份快照', () async {
      final container = containerWith();
      final snapshot = await container.read(installedAppsProvider.future);
      expect(snapshot.error, isNull);
      expect(snapshot.apps.map((app) => app.packageName), [
        'com.example.chat',
        'com.android.systemui',
        'com.example.maps',
      ]);
      expect(snapshot.packageNames, {
        'com.android.systemui',
        'com.example.maps',
        'com.example.chat',
      });
    });

    test('通道缺失时给空列表 + 可读原因，而不是抛异常', () async {
      final container = ProviderContainer(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(MemoryLegacyPrefsStore()),
          installedAppsSourceProvider.overrideWithValue(_FailingAppsSource()),
        ],
      );
      addTearDown(container.dispose);
      final snapshot = await container.read(installedAppsProvider.future);
      expect(snapshot.apps, isEmpty);
      expect(snapshot.error, isNotNull);
      // A broken channel looks like a device without apps, so report value plus error
      expect(container.read(installedAppsProvider).hasError, isFalse);
    });
  });

  group('互斥写入', () {
    /// Excluding an app clears it from blocked, HTTPS-check and app rules. Packages are
    /// seeded as `List<String>` because that is what `putStringSet` stores
    test('排除应用清掉另外三处', () {
      final container = containerWith({
        'dns_vpn_prefs': {
          'excluded_app_packages': <String>[],
          'blocked_app_packages': <String>['com.example.maps'],
          'blocked_apps_enabled': true,
          'http_inspection_app_packages': <String>['com.example.maps'],
          'http_inspection_enabled': true,
          'app_allowlist_rules_json':
              '{"com.example.maps":["api.example.com"]}',
        },
      });
      final settings = container.read(legacySettingsProvider);
      final excluded = {...settings.excludedPackages, 'com.example.maps'};
      settings.setExcludedPackages(excluded);
      settings.setBlockedApps(
        packages: settings.blockedAppPackages.difference(excluded),
        enabled: settings.blockedAppsEnabled,
      );
      settings.setHttpInspectionApps(
        packages: settings.httpInspectionPackages.difference(excluded),
        enabled: settings.httpInspectionEnabled,
      );
      settings.setAppAllowlistRules({
        for (final entry in settings.appAllowlistRules.entries)
          if (!excluded.contains(entry.key)) entry.key: entry.value,
      });
      container.read(legacySettingsRevisionProvider.notifier).bump();

      final next = container.read(legacySettingsProvider);
      expect(next.excludedPackages, {'com.example.maps'});
      expect(next.blockedAppPackages, isEmpty);
      expect(next.httpInspectionPackages, isEmpty);
      expect(next.appAllowlistRules, isEmpty);
      expect(next.blockedAppsEnabled, isTrue);
      expect(next.httpInspectionEnabled, isTrue);
    });

    test('HTTPS 检查应用清掉排除与禁止联网', () {
      final container = containerWith({
        'dns_vpn_prefs': {
          'excluded_app_packages': <String>['com.example.chat'],
          'blocked_app_packages': <String>['com.example.chat'],
          'http_inspection_app_packages': <String>[],
        },
      });
      final settings = container.read(legacySettingsProvider);
      const chosen = {'com.example.chat'};
      settings.setHttpInspectionApps(
        packages: chosen,
        enabled: settings.httpInspectionEnabled,
      );
      settings.setExcludedPackages(
        settings.excludedPackages.difference(chosen),
      );
      settings.setBlockedApps(
        packages: settings.blockedAppPackages.difference(chosen),
        enabled: settings.blockedAppsEnabled,
      );
      container.read(legacySettingsRevisionProvider.notifier).bump();

      final next = container.read(legacySettingsProvider);
      expect(next.httpInspectionPackages, chosen);
      expect(next.excludedPackages, isEmpty);
      expect(next.blockedAppPackages, isEmpty);
    });
  });

  group('互斥清洗不能把自己清掉', () {
    /// Regression: `_dropOverlaps` once read back the set it had just written, wiping the selection
  });

  group('过滤 / 排序的落盘', () {
    test('四个页面的 filter/sort 键互不干扰', () {
      final container = containerWith({
        'dns_vpn_prefs': {
          'excluded_apps_filter': 'SYSTEM',
          'excluded_apps_sort': 'PACKAGE_DESC',
          'app_allowlist_filter': 'ALL',
          'app_allowlist_sort': 'LABEL_DESC',
        },
      });
      final settings = container.read(legacySettingsProvider);
      expect(settings.excludedAppsFilterRaw, 'SYSTEM');
      expect(settings.excludedAppsSortRaw, 'PACKAGE_DESC');
      expect(settings.appAllowlistFilterRaw, 'ALL');
      expect(settings.appAllowlistSortRaw, 'LABEL_DESC');

      settings.setExcludedAppsFilterRaw(AppListFilter.selected.storageValue);
      container.read(legacySettingsRevisionProvider.notifier).bump();
      final next = container.read(legacySettingsProvider);
      expect(next.excludedAppsFilterRaw, 'SELECTED');
      expect(next.appAllowlistFilterRaw, 'ALL');
    });
  });

  group('应用独立规则', () {
    test('放行域名按 JSON 对象读写，空数组的包名被丢弃', () {
      final container = containerWith({
        'dns_vpn_prefs': {
          'app_allowlist_rules_json':
              '{"com.example.maps":["a.example.com","b.example.com"],'
              '"com.example.chat":[]}',
          'app_allowlist_enabled': true,
        },
      });
      final settings = container.read(legacySettingsProvider);
      expect(settings.appAllowlistRules, {
        'com.example.maps': {'a.example.com', 'b.example.com'},
      });
      expect(settings.appAllowlistEnabled, isTrue);
    });
  });

  group('httpsInspectionOperational', () {
    test('需要证书就绪 + 总开关 + 至少一个应用', () {
      Map<String, Map<String, Object>> seed({
        required String backend,
        required bool ready,
        required bool enabled,
        required List<String> apps,
      }) => {
        'dns_vpn_prefs': {
          'https_inspection_ca_backend': backend,
          'https_inspection_ready': ready,
          'http_inspection_enabled': enabled,
          'http_inspection_app_packages': apps,
        },
      };

      bool operational(Map<String, Map<String, Object>> data) =>
          containerWith(data)
              .read(legacySettingsProvider)
              .httpsInspectionOperational;

      expect(
        operational(
          seed(
            backend: 'go-v1',
            ready: true,
            enabled: true,
            apps: ['com.example.maps'],
          ),
        ),
        isTrue,
      );
      expect(
        operational(
          seed(
            backend: 'legacy',
            ready: true,
            enabled: true,
            apps: ['com.example.maps'],
          ),
        ),
        isFalse,
      );
      expect(
        operational(
          seed(
            backend: 'go-v1',
            ready: false,
            enabled: true,
            apps: ['com.example.maps'],
          ),
        ),
        isFalse,
      );
      expect(
        operational(
          seed(
            backend: 'go-v1',
            ready: true,
            enabled: false,
            apps: ['com.example.maps'],
          ),
        ),
        isFalse,
      );
      expect(
        operational(
          seed(backend: 'go-v1', ready: true, enabled: true, apps: []),
        ),
        isFalse,
      );
    });
  });
}

class _FakeAppsSource implements InstalledAppsSource {
  _FakeAppsSource(this.apps);

  List<InstalledApp> apps;
  int listCalls = 0;

  @override
  Future<List<InstalledApp>> list() async {
    listCalls++;
    return apps;
  }

  @override
  Future<Map<String, int>> resolveUids(Iterable<String> packages) async => {
    for (final app in apps)
      if (packages.contains(app.packageName)) app.packageName: app.uid,
  };

  @override
  Future<bool> isSelf(String packageName) async => false;

  @override
  Future<Map<String, Uint8List>> loadIcons(Iterable<String> packages) async =>
      const {};
}

class _FailingAppsSource implements InstalledAppsSource {
  @override
  Future<List<InstalledApp>> list() async =>
      throw MissingPluginException('模拟宿主没有 apps 通道');

  @override
  Future<Map<String, int>> resolveUids(Iterable<String> packages) async =>
      throw MissingPluginException('模拟宿主没有 apps 通道');

  @override
  Future<bool> isSelf(String packageName) async =>
      throw MissingPluginException('模拟宿主没有 apps 通道');

  @override
  Future<Map<String, Uint8List>> loadIcons(Iterable<String> packages) async =>
      throw MissingPluginException('模拟宿主没有 apps 通道');
}
