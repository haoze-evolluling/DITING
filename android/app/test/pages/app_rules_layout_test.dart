import 'dart:typed_data';

import 'package:diting_android/data/native/apps_bridge.dart';
import 'package:diting_android/pages/hub/app_rules_page.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_host.dart';
import '../support/test_hooks.dart';

void main() {
  installGlobalTestHooks();

  testWidgets('应用分组标题位于搜索框上方', (tester) async {
    tester.view.physicalSize = const Size(1170, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(MemoryLegacyPrefsStore()),
          installedAppsSourceProvider.overrideWithValue(_TestAppsSource()),
        ],
        child: const AppHost(child: AppRulesPage()),
      ),
    );
    await tester.pumpAndSettle();

    final heading = find.text('应用（2）');
    final search = find.byType(SearchField);
    expect(heading, findsOneWidget);
    expect(search, findsOneWidget);
    expect(
      tester.getTopLeft(search).dy,
      greaterThan(tester.getBottomLeft(heading).dy),
    );
  });
}

class _TestAppsSource implements InstalledAppsSource {
  static const _apps = [
    InstalledApp(
      packageName: 'com.example.chat',
      label: 'Chat',
      isSystem: false,
      uid: 10102,
    ),
    InstalledApp(
      packageName: 'com.example.maps',
      label: '地图',
      isSystem: false,
      uid: 10101,
    ),
  ];

  @override
  Future<List<InstalledApp>> list() async => _apps;

  @override
  Future<Map<String, int>> resolveUids(Iterable<String> packages) async => {
    for (final app in _apps)
      if (packages.contains(app.packageName)) app.packageName: app.uid,
  };

  @override
  Future<bool> isSelf(String packageName) async => false;

  @override
  Future<Map<String, Uint8List>> loadIcons(Iterable<String> packages) async =>
      const {};
}
