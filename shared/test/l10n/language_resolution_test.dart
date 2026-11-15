// Regression cover for the "跟随系统" (follow system) language path.
//
// The reported symptom was an English UI on a Chinese device: `MaterialApp.locale == null`
// resolves through `basicLocaleListResolution`, whose last resort is `supportedLocales.first`.
// gen-l10n sorts that list alphabetically, so the fallback silently became English for an
// empty locale list (engine not ready yet) and for every language the app does not ship —
// while the product rule (`languageInterfaceFooter`) is that those show Chinese.
// `preferred-supported-locales` in `l10n.yaml` pins Chinese first; these tests keep it that way.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/app/l10n/ui_strings.dart';
import 'package:diting_shared/ui/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The delegate list the app roots mount; keep in step with `DitingApp` / `DesktopApp`.
const _delegates = <LocalizationsDelegate<dynamic>>[
  AppUiLocalizations.delegate,
  AppL10n.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

Widget _probe() => MaterialApp(
  localizationsDelegates: _delegates,
  supportedLocales: AppL10n.supportedLocales,
  // No `locale`: this is the "follow system" path under test.
  home: Builder(
    builder: (context) => Column(
      children: [
        Text(context.l10n.appTitle),
        Text(UiLocalizations.of(context).cancel),
      ],
    ),
  ),
);

void main() {
  group('supportedLocales 顺序', () {
    test('中文是兜底语言', () {
      expect(AppL10n.supportedLocales.first, const Locale('zh'));
      expect(AppL10n.supportedLocales, const [Locale('zh'), Locale('en')]);
    });

    test('系统语言解析：中文/英文按语言匹配，其余落到中文', () {
      Locale resolve(List<Locale> preferred) =>
          basicLocaleListResolution(preferred, AppL10n.supportedLocales);

      // Chinese devices, including the script-tagged form Android sends.
      expect(resolve(const [Locale('zh', 'CN')]), const Locale('zh'));
      expect(resolve(const [Locale('zh', 'TW')]), const Locale('zh'));
      expect(
        resolve(const [Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')]),
        const Locale('zh'),
      );
      // English keeps matching by language, so an en device never falls back to Chinese.
      expect(resolve(const [Locale('en', 'US')]), const Locale('en'));
      // No resources for the language, and the ambiguous cases: Chinese, not English.
      expect(resolve(const [Locale('ja', 'JP')]), const Locale('zh'));
      expect(resolve(const [Locale('fr')]), const Locale('zh'));
      expect(resolve(const [Locale('und')]), const Locale('zh'));
      // The engine reports no locale before the platform hands one over.
      expect(resolve(const []), const Locale('zh'));
      // A later preferred language still wins over the fallback: the device asked for English
      // second, so it is not a "no resources" case.
      expect(resolve(const [Locale('ja', 'JP'), Locale('en', 'US')]), const Locale('en'));
    });
  });

  group('跟随系统的界面语言', () {
    Future<void> pumpWith(WidgetTester tester, List<Locale> locales) async {
      tester.platformDispatcher.localesTestValue = locales;
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(_probe());
      await tester.pumpAndSettle();
    }

    testWidgets('中文系统显示中文', (tester) async {
      await pumpWith(tester, const [Locale('zh', 'CN')]);
      expect(find.text('谛听 DITING'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    });

    testWidgets('英文系统显示英文', (tester) async {
      await pumpWith(tester, const [Locale('en', 'US')]);
      expect(find.text('DITING'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('系统语言无资源时显示中文而不是英文', (tester) async {
      await pumpWith(tester, const [Locale('ja', 'JP')]);
      expect(find.text('谛听 DITING'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    });

    testWidgets('尚未拿到系统语言时显示中文而不是英文', (tester) async {
      await pumpWith(tester, const []);
      expect(find.text('谛听 DITING'), findsOneWidget);
    });

    testWidgets('运行中系统语言切换后立即跟随', (tester) async {
      await pumpWith(tester, const [Locale('en', 'US')]);
      expect(find.text('DITING'), findsOneWidget);

      tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
      await tester.pumpAndSettle();
      expect(find.text('谛听 DITING'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    });
  });
}
