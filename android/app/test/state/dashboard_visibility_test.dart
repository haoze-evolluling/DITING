import 'package:diting_android/data/dashboard_models.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MemoryLegacyPrefsStore store;

  setUp(() => store = MemoryLegacyPrefsStore());

  ProviderContainer container({AppWorkMode mode = AppWorkMode.normal}) {
    final instance = ProviderContainer(
      overrides: [
        legacyPrefsStoreProvider.overrideWithValue(store),
        workModeProvider.overrideWith(() => _Mode(mode)),
      ],
    );
    addTearDown(instance.dispose);
    return instance;
  }

  test('普通模式照常显示网速卡片', () {
    expect(
      container().read(visibleDashboardWidgetsProvider),
      contains(DashboardWidget.networkSpeed),
    );
  });

  test('极速模式与普通模式显示同一套卡片', () {
    final normal = container().read(visibleDashboardWidgetsProvider);
    final instance = container(mode: AppWorkMode.express);
    expect(instance.read(dashboardWidgetsProvider), defaultDashboardWidgets);
    final express = instance.read(visibleDashboardWidgetsProvider);
    expect(express, normal);
    expect(express, contains(DashboardWidget.networkSpeed));
  });

  test('极速模式下重排卡片', () {
    final instance = container(mode: AppWorkMode.express);
    final notifier = instance.read(dashboardWidgetsProvider.notifier);
    final visible = instance.read(visibleDashboardWidgetsProvider);
    final last = visible.last;

    notifier.moveVisible(visible, visible.length - 1, 0);

    final next = instance.read(dashboardWidgetsProvider);
    expect(next, hasLength(visible.length));
    expect(next.first, last);
    expect(instance.read(visibleDashboardWidgetsProvider).first, last);
  });
}

class _Mode extends WorkModeNotifier {
  _Mode(this.mode);

  final AppWorkMode mode;

  @override
  AppWorkMode build() => mode;
}
