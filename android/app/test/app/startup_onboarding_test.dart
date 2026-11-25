import 'package:diting_android/app/app.dart';
import 'package:diting_android/app/initial_agreement.dart';
import 'package:diting_android/pages/mode/mode_onboarding_page.dart';
import 'package:diting_android/pages/mode/mode_select_page.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/test_hooks.dart';

void main() {
  installGlobalTestHooks();

  Future<void> pumpApp(
    WidgetTester tester, {
    required List<Override> overrides,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const DitingApp()),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('首次启动同意须知后进入模式选择', (tester) async {
    await pumpApp(tester, overrides: const []);
    expect(find.byType(InitialAgreementDialog), findsOneWidget);

    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();

    expect(find.byType(InitialAgreementDialog), findsNothing);
    expect(find.byType(ModeSelectPage), findsOneWidget);
  });

  testWidgets('已选模式但未完成引导时直接展示引导页', (tester) async {
    await pumpApp(
      tester,
      overrides: [
        initialAgreementProvider.overrideWith(InitialAgreementAccepted.new),
        workModeSelectedProvider.overrideWith(WorkModeSelected.new),
      ],
    );

    expect(find.byType(ModeOnboardingPage), findsOneWidget);
    expect(find.text('引导'), findsOneWidget);
  });

  test('两种模式的介绍说清数据面差异、数据独立与功能中心精简', () {
    final l10n = lookupAppL10n(const Locale('zh'));

    // 普通模式全隧道，简洁模式只过滤 DNS。
    expect(l10n.workModeNormalSummary, contains('全隧道'));
    expect(l10n.workModeExpressSummary, contains('只过滤 DNS'));
    expect(l10n.workModeExpressSummary, contains('直连'));

    expect(l10n.modeSharedNote, contains('数据'));
    expect(l10n.modeSharedNote, contains('互不相通'));
    expect(l10n.modeSharedNote, contains('功能中心默认少显示'));

    expect(
      [
        l10n.modeExpressFeature1,
        l10n.modeExpressFeature2,
        l10n.modeExpressFeature3,
        l10n.modeExpressFeature4,
      ],
      [
        '纯 DNS 过滤',
        '独立数据存储',
        '默认更精简的功能中心',
        '有 Root 更彻底',
      ],
    );

    expect(l10n.onboardingTipExpress1, contains('只过滤 DNS'));
    // 悬浮日志窗由两种模式共用的服务提供，旧文案的模式限制已移除。
    expect(l10n.logRetentionOverlayNote, isNot(contains('模式')));
  });
}
