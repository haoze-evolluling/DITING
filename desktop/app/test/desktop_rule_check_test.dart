// Desktop tools branch, rule simulator (desktop parity):
// `/filter/check` judges one domain and the page repeats its verdict.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_rule_check_models.dart';
import 'package:diting_desktop/pages/tools/desktop_rule_check_page.dart';
import 'package:diting_desktop/pages/hub/desktop_hub_page.dart';
import 'package:diting_desktop/widgets/desktop_picker.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';
import 'support/desktop_page_harness.dart';

void main() {
  Future<FakeDesktopBackend> pumpRuleCheck(
    WidgetTester tester, {
    FakeDesktopBackend? backend,
    Size size = const Size(1280, 900),
  }) => pumpDesktopPage(
    tester,
    path: DesktopRuleCheckPage.path,
    backend: backend,
    size: size,
  );

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopRuleCheckPage)).l10n;


  test('重写字段缺失时不算重写', () {
    final pass = DesktopRuleCheckResult.fromJson(const {
      'blocked': false,
      'action': 'pass',
      'reason': '正常直连解析',
    });
    expect(pass.blocked, isFalse);
    expect(pass.isRewrite, isFalse);
    expect(pass.rewritten, isNull);

    final rewrite = DesktopRuleCheckResult.fromJson(const {
      'action': 'rewrite',
      'rewritten': {
        'rcode': 0,
        'summary': ['A 1.2.3.4'],
      },
    });
    expect(rewrite.isRewrite, isTrue);
    expect(rewrite.rewritten!.summary, ['A 1.2.3.4']);
    expect(desktopRcodeName(3), 'NXDOMAIN');
    expect(desktopRcodeName(9), 'RCODE 9');
  });

  testWidgets('未检测时只给提示', (tester) async {
    await pumpRuleCheck(tester);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopToolsRuleIdle), findsOneWidget);
    expect(find.byType(DashboardChip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('检测提交域名与记录类型并显示拦截判定', (tester) async {
    final backend = await pumpRuleCheck(tester);
    final l10n = l10nOf(tester);

    await tester.enterText(find.byType(TextField).first, 'ads.example.com');
    await tapAt(tester, find.text(l10n.desktopToolsRuleRun));

    expect(backend.ruleCheckUpdates.single, {
      'domain': 'ads.example.com',
      'qtype': 'A',
    });
    expect(find.text(l10n.desktopToolsRuleBlocked), findsOneWidget);
    expect(find.text('||ads.example^'), findsOneWidget);
    expect(find.text('广告拦截'), findsOneWidget);
    expect(find.text('命中拦截规则'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('示例标签直接填充并运行', (tester) async {
    final backend = await pumpRuleCheck(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, find.text('baidu.com'));
    expect(backend.ruleCheckUpdates.single['domain'], 'baidu.com');
    expect(
      find.text(l10n.desktopToolsRuleBlocked),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换记录类型后按所选类型提交', (tester) async {
    final backend = await pumpRuleCheck(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, find.byType(DesktopPicker));
    await tapAt(tester, find.text(l10n.desktopToolsRuleQtypeOption('AAAA')));
    await tester.enterText(find.byType(TextField).first, 'example.com');
    await tapAt(tester, find.text(l10n.desktopToolsRuleRun));

    expect(backend.ruleCheckUpdates.single['qtype'], 'AAAA');
    expect(tester.takeException(), isNull);
  });

  testWidgets('重写命中显示应答码与记录', (tester) async {
    await pumpRuleCheck(
      tester,
      backend: FakeDesktopBackend(
        ruleCheck: ruleCheckPayload(
          blocked: false,
          action: 'rewrite',
          matchedRule: r'||rewrite.example^$dnsrewrite=1.2.3.4',
          listName: '自定义规则',
          reason: '命中重写规则',
          rewritten: {
            'rcode': 0,
            'summary': ['rewrite.example. 60 IN A 1.2.3.4'],
          },
        ),
      ),
    );
    final l10n = l10nOf(tester);

    await tapAt(tester, find.text('baidu.com'));
    expect(
      find.text(l10n.desktopToolsRuleRewritten('NOERROR')),
      findsOneWidget,
    );
    expect(
      find.text('rewrite.example. 60 IN A 1.2.3.4'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('重写为 NODATA 时说明不返回记录', (tester) async {
    await pumpRuleCheck(
      tester,
      backend: FakeDesktopBackend(
        ruleCheck: ruleCheckPayload(
          blocked: false,
          action: 'rewrite',
          matchedRule: r'||empty.example^$dnsrewrite=NXDOMAIN',
          listName: '自定义规则',
          reason: '命中重写规则',
          rewritten: {'rcode': 3, 'summary': const <String>[]},
        ),
      ),
    );
    final l10n = l10nOf(tester);

    await tapAt(tester, find.text('baidu.com'));
    expect(
      find.text(l10n.desktopToolsRuleRewriteEmpty),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('检测失败时说明原因且不显示旧判定', (tester) async {
    final backend = FakeDesktopBackend()..rejectWrites = true;
    await pumpRuleCheck(tester, backend: backend);
    final l10n = l10nOf(tester);

    await tapAt(tester, find.text('baidu.com'));
    expect(
      find.text(l10n.desktopToolsRuleFailed('write rejected')),
      findsOneWidget,
    );
    expect(find.text(l10n.desktopToolsRuleBlocked), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('工具页可进入规则检测子页', (tester) async {
    await pumpDesktopPage(tester, path: Routes.hub);
    final l10n = tester.element(find.byType(DesktopFeatureHubPage)).l10n;

    await tapAt(tester, find.text(l10n.desktopToolsRulePageTitle));
    expect(find.byType(DesktopRuleCheckPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗单列且不横向溢出', (tester) async {
    await pumpRuleCheck(tester, size: const Size(390, 844));
    final l10n = l10nOf(tester);
    await tapAt(tester, find.text('baidu.com'));
    expect(find.text(l10n.desktopToolsRuleBlocked), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
