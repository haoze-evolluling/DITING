// Desktop rebuild guards (docs/development/flutter-desktop-ui.md §8): the shell is the FlClash
// sidebar on a wide window and the shared dock on a narrow one, the branch table matches Android,
// and no desktop-only visual language may appear.

import 'dart:io';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/prefs/legacy_prefs_store.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/desktop/app/desktop_app.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/data/api/desktop_live_providers.dart';
import 'package:diting/desktop/pages/desktop_pages.dart';
import 'package:diting/desktop/pages/hub/desktop_hub_page.dart';
import 'package:diting/desktop/pages/home/desktop_home_page.dart';
import 'package:diting/desktop/pages/logs/desktop_logs_page.dart';
import 'package:diting/desktop/pages/settings/desktop_settings_page.dart';
import 'package:diting/desktop/pages/tools/desktop_tools_page.dart';
import 'package:diting/desktop/pages/traffic/desktop_traffic_page.dart';
import 'package:diting/desktop/router.dart';
import 'package:diting/desktop/shell/desktop_shell.dart';
import 'package:diting/routes/branches.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

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
  FakeDesktopBackend? backend,
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
        desktopPollingEnabledProvider.overrideWithValue(false),
        desktopLiveEnabledProvider.overrideWithValue(false),
        desktopApiClientProvider.overrideWithValue(
          (backend ?? FakeDesktopBackend()).client(),
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
    testWidgets('分支 $location 由 CommonScaffold 承载并说明状态', (tester) async {
      await _pumpDesktop(tester, initialLocation: location);

      expect(find.byType(CommonScaffold), findsOneWidget);
      // The title comes from the ARB, never from a literal in the page.
      final scaffold = tester.widget<CommonScaffold>(
        find.byType(CommonScaffold),
      );
      expect(scaffold.title, isNotNull);
      expect(scaffold.title, isNotEmpty);
      if (location == Routes.home) {
        // Home renders the board from the service snapshot instead of an empty state.
        expect(find.byType(NullStatus), findsNothing);
      } else if (location == Routes.hub) {
        // The hub is a real feature list now; its resolution section opens the upstream page.
        expect(find.byType(DesktopFeatureHubPage), findsOneWidget);
        expect(find.byType(AppBarClearance), findsNothing);
      } else if (location == Routes.settings) {
        // Settings is a real entry list now; its rows open the desktop sub-pages.
        expect(find.byType(DesktopSettingsPage), findsOneWidget);
        expect(find.byType(AppBarClearance), findsNothing);
      } else if (location == Routes.tools) {
        // The tools page runs the port probe on demand; no pending empty state.
        expect(find.byType(DesktopToolsPage), findsOneWidget);
        expect(find.byType(AppBarClearance), findsNothing);
      } else if (location == Routes.traffic) {
        // The device page is wired to `/clients` and `/status`; no pending empty state.
        expect(find.byType(DesktopTrafficPage), findsOneWidget);
        expect(find.byType(AppBarClearance), findsNothing);
      } else if (location == Routes.logs) {
        // Logs is wired to the service's log API: summary figures and the query table, with no
        // full-page pending state left behind.
        expect(find.byType(DesktopLogsPage), findsOneWidget);
        expect(find.byType(AppBarClearance), findsNothing);
      } else {
        // Unwired branches say so instead of inventing values, centered like Android's own
        // full-page empty states.
        expect(find.byType(NullStatus), findsOneWidget);
        expect(find.byType(AppBarClearance), findsOneWidget);
      }
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
  testWidgets('宽屏是侧栏，不叠浮条也不降级成 NavigationBar', (tester) async {
    await _pumpDesktop(tester, size: const Size(1280, 800));

    expect(find.byType(DesktopShell), findsOneWidget);
    expect(find.byType(NavigationSidebar), findsOneWidget);
    expect(find.byType(NavigationDock), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    // Nothing floats over the page, so pages reserve only the plain bottom gap.
    expect(
      DockInsetScope.of(tester.element(find.byType(CommonScaffold))),
      DockInsetScope.pageBottomGap,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏用浮条 NavigationDock，且为内容预留间隙', (tester) async {
    await _pumpDesktop(tester, size: const Size(390, 844));

    expect(find.byType(NavigationSidebar), findsNothing);
    expect(find.byType(NavigationDock), findsOneWidget);
    expect(
      DockInsetScope.of(tester.element(find.byType(CommonScaffold))),
      greaterThan(DockInsetScope.pageBottomGap),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击侧栏切换分支，并保持分支表顺序', (tester) async {
    await _pumpDesktop(tester, size: const Size(1280, 800));
    expect(find.byType(DesktopHomePage), findsOneWidget);

    final l10n = tester.element(find.byType(DesktopHomePage)).l10n;
    final sidebar = find.byType(NavigationSidebar);
    final hub = find.descendant(
      of: sidebar,
      matching: find.text(l10n.bottomBarFeatureHub),
    );
    expect(hub, findsOneWidget);

    await tester.tap(hub);
    await tester.pumpAndSettle();

    expect(find.byType(DesktopFeatureHubPage), findsOneWidget);
    expect(find.byType(DesktopHomePage), findsNothing);
  });

  testWidgets('折叠侧栏后仍可切换分支', (tester) async {
    await _pumpDesktop(tester, size: const Size(1280, 800));
    final l10n = tester.element(find.byType(DesktopHomePage)).l10n;

    final collapsedWidth = tester.getSize(find.byType(NavigationSidebar)).width;
    await tester.tap(find.byTooltip(l10n.uiShowLess));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(NavigationSidebar)).width,
      lessThan(collapsedWidth),
    );
    // Collapsed, the labels are clipped away and every row is identified by its tooltip.
    // Collapsed, only the icons are inside the clip, so the row is hit through its glyph.
    final rows = find.descendant(
      of: find.byType(NavigationSidebar),
      matching: find.byType(AnimatedGlyph),
    );
    expect(rows, findsNWidgets(branchOrder.length));
    await tester.tap(rows.at(branchIndexOf(Routes.logs)));
    await tester.pumpAndSettle();

    expect(find.byType(DesktopLogsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
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
