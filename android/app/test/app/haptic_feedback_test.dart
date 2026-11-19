import 'package:diting_android/app/app.dart';
import 'package:diting_android/state/server_status_providers.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_dns_server_controller.dart';
import '../support/test_hooks.dart';

void main() {
  installGlobalTestHooks();

  late List<String> haptics;

  setUp(() {
    haptics = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add('${call.arguments}');
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    required String workMode,
    bool hapticEnabled = true,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...appTestOverrides(),
          legacyPrefsStoreProvider.overrideWithValue(
            MemoryLegacyPrefsStore({
              'diting_settings': {'app_work_mode': workMode},
              'diting_dns_mode_prefs': <String, Object?>{},
            }),
          ),
          dnsServerControllerProvider.overrideWithValue(
            FakeDnsServerController(),
          ),
          hapticProvider.overrideWith(() => _HapticSetting(hapticEnabled)),
        ],
        child: const DitingApp(),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('服务器模式底栏切页有触感反馈', (tester) async {
    await pumpApp(tester, workMode: 'dns');

    await tester.tap(find.text('功能中心').last);
    await tester.pump();

    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('普通模式底栏切页仍只反馈一次', (tester) async {
    await pumpApp(tester, workMode: 'normal');

    await tester.tap(find.text('功能中心').last);
    await tester.pump();

    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('关闭界面触感后底栏切页静音', (tester) async {
    await pumpApp(tester, workMode: 'dns', hapticEnabled: false);

    await tester.tap(find.text('功能中心').last);
    await tester.pump();

    expect(haptics, isEmpty);
  });

  testWidgets('从关闭切换到开启时确认一次反馈', (tester) async {
    final container = ProviderContainer(
      overrides: [
        legacyPrefsStoreProvider.overrideWithValue(
          MemoryLegacyPrefsStore({
            'diting_settings': {'app_work_mode': 'normal'},
            LegacySettings.uiContainer: {'bottom_bar_haptic_enabled': false},
          }),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(hapticProvider), isFalse);
    container.read(hapticProvider.notifier).toggle(true);
    await tester.pump();

    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });
}

class _HapticSetting extends HapticNotifier {
  _HapticSetting(this.value);

  final bool value;

  @override
  bool build() => value;
}
