// Layout and dialog regressions over every route at three sizes, the first-run
// agreement, and the dialog field lifecycle.

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/app/app.dart';
import 'package:diting/app/initial_agreement.dart';
import 'package:diting/pages/system/unknown_route_page.dart';
import 'package:diting/router.dart';
import 'package:diting/state/settings_providers.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_host.dart';
import 'support/route_catalog.dart';
import 'support/test_hooks.dart';

void main() {
  group('全路由布局', _layoutRegression);
  group('首启须知', _initialAgreement);
  group('弹窗输入框生命周期', _dialogField);
  group('分段控件标签', _segmentedLabels);
}

/// Long English labels used to be ellipsized to "Single re…" in the resolution card.
void _segmentedLabels() {
  Future<void> pumpControl(
    WidgetTester tester,
    List<(int, String)> segments,
  ) async {
    await tester.pumpWidget(
      AppHost(
        child: Center(
          child: SizedBox(
            width: 338,
            child: SegmentedControl<int>(
              segments: segments,
              value: 0,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('长标签换行而不是省略', (tester) async {
    await pumpControl(tester, const [
      (0, 'Single resolver'),
      (1, 'Smart select'),
      (2, 'Parallel'),
      (3, 'Primary backup'),
    ]);
    expect(tester.takeException(), isNull);
    final label = tester.widget<Text>(find.text('Single resolver'));
    expect(label.maxLines, 2, reason: '英文长标签应换行显示完整文案');
    expect(
      tester.getSize(find.byType(SegmentedControl<int>)).height,
      greaterThan(44),
      reason: '两行文案需要更高的控件，否则会被裁切',
    );
  });

  testWidgets('短标签保持单行高度', (tester) async {
    await pumpControl(tester, const [
      (0, '单服务商'),
      (1, '智能选择'),
      (2, '并行'),
      (3, '主备'),
    ]);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(SegmentedControl<int>)).height,
      44,
    );
    expect(tester.widget<Text>(find.text('单服务商')).maxLines, 1);
  });
}

/// Layout regression over every route at three widths; overflow surfaces via `takeException()`
void _layoutRegression() {
  installGlobalTestHooks();

  /// Every route, including the rule, subscription and mode pages beyond the six tabs.
  final routes = <String>[
    Routes.hub,
    Routes.logs,
    Routes.traffic,
    Routes.tools,
    Routes.settings,
    Routes.batchEditor,
    Routes.subscriptions,
    Routes.about,
    Routes.modeSelect,
    Routes.modeOnboarding,
    ...topLevelRoutes.values,
    ...idRoutes.values,
  ];

  /// (label, logical size): 320 iPhone SE, 412 mainstream Android, 834 iPad, crossing the 600
  /// breakpoint
  const sizes = <(String, Size)>[
    ('se', Size(320, 568)),
    ('pixel', Size(412, 915)),
    ('tablet', Size(834, 1112)),
  ];

  Future<void> pumpAt(
    WidgetTester tester, {
    required String route,
    required Size size,
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: appTestOverrides(),
        child: DitingApp(initialLocation: route),
      ),
    );
    // The localization delegate loads async: pump once more for labels.
    await tester.pump();
    await tester.pumpAndSettle();
  }

  for (final (sizeLabel, size) in sizes) {
    testWidgets('所有路由在 $sizeLabel 尺寸下无溢出', (tester) async {
      for (final route in routes) {
        await pumpAt(tester, route: route, size: size);
        expectNoLayoutFailure(
          tester,
          '$route 在 $sizeLabel (${size.width}x${size.height})',
        );
      }
    });
  }

  testWidgets('小屏 + 1.4 倍字号下所有路由无溢出', (tester) async {
    // 1.4 is the `clampTextScale` upper bound, the largest size supported.
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final route in routes) {
      await pumpAt(tester, route: route, size: const Size(320, 568));
      expectNoLayoutFailure(tester, '$route 在 320 宽 + 1.4 倍字号下');
    }
  });
}

/// One pump must neither throw nor fall through to the unregistered-route fallback page.
void expectNoLayoutFailure(WidgetTester tester, String context) {
  expect(tester.takeException(), isNull, reason: '$context 布局异常');
  expect(
    find.byType(UnknownRoutePage),
    findsNothing,
    reason: '$context 路由未注册，落到了兜底页',
  );
}

/// Guards the first-run agreement dialog: it blocks the page and its text must match 1.4.3 exactly
void _initialAgreement() {
  installGlobalTestHooks(skipInitialAgreement: false);

  Future<void> pumpApp(WidgetTester tester, {required bool accepted}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (accepted)
            initialAgreementProvider.overrideWith(InitialAgreementAccepted.new),
        ],
        child: DitingApp(initialLocation: '/'),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('未确认时弹出使用须知', (tester) async {
    await pumpApp(tester, accepted: false);
    expect(find.byType(InitialAgreementDialog), findsOneWidget);
    expect(find.text('使用须知与免责声明'), findsOneWidget);
    expect(find.text('同意并继续'), findsOneWidget);
    expect(find.text('不同意并退出'), findsOneWidget);
  });

  testWidgets('点「同意并继续」后弹窗消失且写盘', (tester) async {
    await pumpApp(tester, accepted: false);
    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();

    expect(find.byType(InitialAgreementDialog), findsNothing);
    // accept() sets both memory and disk; the disk key is guarded in `settings_catalog_test.dart`
    final container = ProviderScope.containerOf(
      tester.element(find.byType(InitialAgreementGate)),
    );
    expect(container.read(initialAgreementProvider), isTrue);
  });

  test('条款正文含旧版三段结构与关键句', () {
    final message = lookupAppL10n(const Locale('zh')).agreementMessage;
    // Three headings, separated by `\n\n` in 1.4.3; a missing one means the body changed.
    expect(message, contains('软件说明'));
    expect(message, contains('运行机制与注意事项'));
    expect(message, contains('免责条款'));

    expect(message, contains('普通模式（全隧道深度管控）'));
    expect(message, contains('极速模式（Go 引擎 + DNS 窄路由）'));
    expect(message, contains('独立服务器模式（局域网免 VPN 服务）'));
    expect(message, contains('无任何远程数据上传与隐私追踪'));
    expect(message, contains('1053 端口'));
    expect(message, contains('本软件按现状提供'));
    expect(message, contains('由使用者自行承担'));
  });
}

void _dialogField() {
  testWidgets('弹窗输入框聚焦后提交不会踩 framework 断言', (tester) async {
    String? submitted;
    await tester.pumpWidget(
      AppHost(
        child: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  submitted = await showFloatingDialog<String>(
                    context: context,
                    child: const _FieldDialog(),
                  );
                },
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    // Let the field really take focus; on a device this raises the keyboard.
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'api.example.com');
    await tester.pump();

    await tester.tap(find.text('提交'));
    // One frame lets pop happen, then finish the exit animation: the crash is here.
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(submitted, 'api.example.com');
  });
}

// Regression: disposing the controller right after `showFloatingDialog` returns kills the field

/// Minimal dialog shaped like production: the controller is owned by `State`.
class _FieldDialog extends StatefulWidget {
  const _FieldDialog();

  @override
  State<_FieldDialog> createState() => _FieldDialogState();
}

class _FieldDialogState extends State<_FieldDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: '输入',
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('提交'),
        ),
      ],
      child: TextField(controller: _controller),
    );
  }
}
