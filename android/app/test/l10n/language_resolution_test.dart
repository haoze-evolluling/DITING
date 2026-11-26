import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/app/l10n/ui_strings.dart';
import 'package:diting_android/ui/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppUiLocalizations.delegate,
  AppL10n.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

Widget _probe() => MaterialApp(
  localizationsDelegates: _delegates,
  supportedLocales: AppL10n.supportedLocales,
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

      expect(resolve(const [Locale('zh', 'CN')]), const Locale('zh'));
      expect(resolve(const [Locale('zh', 'TW')]), const Locale('zh'));
      expect(
        resolve(const [Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')]),
        const Locale('zh'),
      );
      expect(resolve(const [Locale('en', 'US')]), const Locale('en'));
      expect(resolve(const [Locale('ja', 'JP')]), const Locale('zh'));
      expect(resolve(const [Locale('fr')]), const Locale('zh'));
      expect(resolve(const [Locale('und')]), const Locale('zh'));
      expect(resolve(const []), const Locale('zh'));
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
