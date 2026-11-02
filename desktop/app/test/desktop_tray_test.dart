// The Windows tray bridge: the label mapping stays complete for every locale,
// and the runner is re-labelled once per locale change (never per rebuild).

import 'package:diting_desktop/data/host/desktop_tray.dart';
import 'package:diting_desktop/widgets/desktop_tray_sync.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _channel = MethodChannel('diting/tray');

void main() {
  test('every supported locale fills every tray label', () {
    for (final locale in AppL10n.supportedLocales) {
      final labels = DesktopTrayLabels.of(lookupAppL10n(locale)).values;
      expect(labels.keys, hasLength(20), reason: '$locale');
      expect(
        labels.values.where((value) => value.trim().isEmpty),
        isEmpty,
        reason: '$locale',
      );
    }
  });

  test('labels are value objects so an unchanged locale sends nothing', () {
    final zh = DesktopTrayLabels.of(lookupAppL10n(const Locale('zh')));
    final zhAgain = DesktopTrayLabels.of(lookupAppL10n(const Locale('zh')));
    final en = DesktopTrayLabels.of(lookupAppL10n(const Locale('en')));
    expect(zh, zhAgain);
    expect(zh.hashCode, zhAgain.hashCode);
    expect(zh, isNot(en));
  });

  testWidgets('pushes the active locale once and again after a switch', (
    tester,
  ) async {
    // The invariant check runs before tearDowns, so the override is reset inside
    // the test body (finally) rather than through addTearDown.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, null),
      );

      Future<void> pumpLocale(Locale locale) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: const [
              AppL10n.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppL10n.supportedLocales,
            home: const DesktopTraySync(child: SizedBox()),
          ),
        );
        await tester.pump();
      }

      await pumpLocale(const Locale('zh'));
      expect(calls, hasLength(1));
      expect(calls.single.method, 'configure');
      final zh = calls.single.arguments as Map<Object?, Object?>;
      expect(zh['open_window'], '打开主界面');

      // An unchanged locale must not re-send on rebuild.
      await pumpLocale(const Locale('zh'));
      expect(calls, hasLength(1));

      await pumpLocale(const Locale('en'));
      expect(calls, hasLength(2));
      final en = calls.last.arguments as Map<Object?, Object?>;
      expect(en['open_window'], 'Open main window');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
