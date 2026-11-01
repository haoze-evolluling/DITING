// Desktop rebuild guards (docs/development/flutter-desktop-ui.md §8): the shell must be the shared
// one, the branch table must match Android, and no desktop-only visual language may appear.

import 'dart:io';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/prefs/legacy_prefs_store.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/desktop/app/desktop_app.dart';
import 'package:diting/desktop/pages/desktop_pages.dart';
import 'package:diting/desktop/router.dart';
import 'package:diting/routes/branches.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('骨架守卫', _skeleton);
  group('视觉语言守卫', _visualLanguage);
  group('响应式守卫', _responsive);
}

Future<void> _pumpDesktop(
  WidgetTester tester, {
  String? initialLocation,
  Size size = const Size(1280, 800),
  Map<String, Map<String, Object?>>? seed,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        legacyPrefsStoreProvider.overrideWithValue(
          MemoryLegacyPrefsStore(seed),
        ),
      ],
      child: DesktopApp(initialLocation: initialLocation),
    ),
  );
  await tester.pumpAndSettle();
}

void _skeleton() {
  test('桌面分支路径与顺序和 Android 分支表一致', () {
    final shell = createDesktopRouter().configuration.routes
        .whereType<StatefulShellRoute>()
        .single;
    final paths = [
      for (final branch in shell.branches)
        (branch.routes.single as GoRoute).path,
    ];
    expect(paths, branchOrder);
    expect(branchOrder, hasLength(6));
  });

  for (final location in branchOrder) {
    testWidgets('分支 $location 由 CommonScaffold + PageBody 承载', (tester) async {
      await _pumpDesktop(tester, initialLocation: location);

      expect(find.byType(CommonScaffold), findsOneWidget);
      expect(find.byType(PageBody), findsOneWidget);
      // The title comes from the ARB, never from a literal in the page.
      final scaffold = tester.widget<CommonScaffold>(
        find.byType(CommonScaffold),
      );
      expect(scaffold.title, isNotNull);
      expect(scaffold.title, isNotEmpty);
      // Unwired branches say so instead of inventing values.
      expect(find.byType(NullStatus), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('未知路由落到桌面兜底页而不是空白', (tester) async {
    await _pumpDesktop(tester, initialLocation: '/no-such-page');
    expect(find.byType(DesktopUnknownRoutePage), findsOneWidget);
    expect(find.byType(CommonScaffold), findsOneWidget);
  });
}

void _visualLanguage() {
  // Each entry is a pattern the desktop rebuild may not reintroduce. The list is intentionally
  // source-level: a widget test cannot tell "same colours by accident" from "same design system".
  const banned = <String, String>{
    'Material 图标字体': r'\bIcons\.',
    '手写圆角': r'BorderRadius\.circular\(',
    '自建配色': r'ColorScheme\.fromSeed',
    '自建主题': r'ThemeData\(',
    '硬编码字号': r'fontSize\s*:',
    '硬编码颜色': r'\bColors\.',
    '硬编码中文': r'''(['"])(?:(?!\1).)*[\u4e00-\u9fff]''',
  };

  final files = Directory('lib/desktop')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();

  test('扫描范围包含桌面源码', () {
    expect(files, isNotEmpty);
  });

  for (final entry in banned.entries) {
    test('lib/desktop 内不出现${entry.key}', () {
      final pattern = RegExp(entry.value);
      final offenders = [
        for (final file in files)
          for (final (index, line) in file.readAsLinesSync().indexed)
            if (pattern.hasMatch(line))
              '${file.path}:${index + 1}: ${line.trim()}',
      ];
      expect(
        offenders,
        isEmpty,
        reason: '改用 lib/ui 与 ARB：\n${offenders.join('\n')}',
      );
    });
  }
}

void _responsive() {
  testWidgets('窄屏用浮条 NavigationDock，且为内容预留间隙', (tester) async {
    await _pumpDesktop(tester, size: const Size(390, 844));

    expect(find.byType(NavigationDock), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final inset = DockInsetScope.of(
      tester.element(find.byType(PageBody).first),
    );
    expect(inset, greaterThan(DockInsetScope.pageBottomGap));
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏降级为 NavigationBar，而不是自造侧栏', (tester) async {
    await _pumpDesktop(tester, size: const Size(1280, 800));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDock), findsNothing);
    final inset = DockInsetScope.of(
      tester.element(find.byType(PageBody).first),
    );
    expect(inset, greaterThan(DockInsetScope.pageBottomGap));
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击底栏切换分支', (tester) async {
    await _pumpDesktop(tester, size: const Size(390, 844));
    expect(find.byType(DesktopHomePage), findsOneWidget);

    // The label follows the active locale, so read it from the live context instead of a literal.
    final hub = tester
        .element(find.byType(DesktopHomePage))
        .l10n
        .bottomBarFeatureHub;
    await tester.tap(find.text(hub));
    await tester.pumpAndSettle();

    expect(find.byType(DesktopFeatureHubPage), findsOneWidget);
    expect(find.byType(DesktopHomePage), findsNothing);
  });

  testWidgets('文字放大后页面不横向溢出', (tester) async {
    await _pumpDesktop(
      tester,
      size: const Size(390, 844),
      seed: {
        'diting_settings': {'app_text_scale': 1.4},
      },
    );
    expect(tester.takeException(), isNull);
  });
}
