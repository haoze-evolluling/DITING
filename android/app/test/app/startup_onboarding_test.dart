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

  test('两种模式的介绍只强调数据独立与功能中心默认精简', () {
    final l10n = lookupAppL10n(const Locale('zh'));

    // 两个摘要都说清「功能一致」，避免读成两套不同能力。
    expect(l10n.workModeNormalSummary, contains('功能与简洁模式完全一致'));
    expect(l10n.workModeExpressSummary, contains('功能与普通模式完全相同'));

    // 选择模式页只列这两处真实差异。
    expect(l10n.modeSharedNote, contains('数据互不相通'));
    expect(l10n.modeSharedNote, contains('功能中心默认少显示'));

    // 简洁模式的四张卡片不再与普通模式重复罗列同一套功能。
    expect(
      [
        l10n.modeExpressFeature1,
        l10n.modeExpressFeature2,
        l10n.modeExpressFeature3,
        l10n.modeExpressFeature4,
      ],
      [
        '功能与普通模式完全一致',
        '独立数据存储',
        '默认更精简的功能中心',
        '随时可恢复',
      ],
    );

    expect(l10n.onboardingTipExpress1, contains('功能完全一致'));
    // 悬浮日志窗由两种模式共用的全隧道服务提供，旧文案的模式限制已移除。
    expect(l10n.logRetentionOverlayNote, isNot(contains('模式')));
  });
}
