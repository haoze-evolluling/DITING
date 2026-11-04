// Desktop hub rewrite page (desktop parity): the console's engine
// switch, default lifetime and rule table. Every figure must come from the service; a switch, a TTL
// or a rule save posts to `/dns/rewrite/*` and the page then shows what the service re-read.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_rewrite_models.dart';
import 'package:diting_desktop/pages/hub/desktop_hub_page.dart';
import 'package:diting_desktop/pages/hub/desktop_rewrite_page.dart';
import 'package:diting_desktop/pages/hub/widgets/rewrite_engine_card.dart';
import 'package:diting_desktop/pages/home/desktop_dashboard.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';
import 'support/desktop_page_harness.dart';

void main() {
  Future<FakeDesktopBackend> pumpRewrite(
    WidgetTester tester, {
    FakeDesktopBackend? backend,
    Size size = const Size(1280, 900),
    String location = DesktopRewritePage.path,
  }) => pumpDesktopPage(
    tester,
    path: location,
    backend: backend,
    size: size,
  );

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopRewritePage)).l10n;

  Finder inEngine(Finder matching) =>
      find.descendant(of: find.byType(RewriteEngineCard), matching: matching);

  /// The page is taller than a window, so a control below the fold has to be scrolled to first.

  /// Lets the current snackbar expire, so the next action's message is the one on screen.

  test('缺字段按零值解析，失败应答码替换类型徽标', () {
    final rule = DesktopRewriteRule.fromJson(const {'domain': 'lan'});
    expect(rule.ips, isEmpty);
    expect(rule.typeLabels, isEmpty);
    expect(rule.hasTarget, isFalse);

    final failure = DesktopRewriteRule.fromJson(const {
      'domain': 'gone.lan',
      'rcode': 'nxdomain',
      'ips': ['10.0.0.1'],
    });
    expect(failure.isRcodeFailure, isTrue);
    expect(failure.typeLabels, ['NXDOMAIN']);

    final mixed = DesktopRewriteRule.fromJson(const {
      'domain': 'mail.lan',
      'txt': ['v=spf1 ~all'],
      'ips': ['10.0.0.5'],
      'records': [
        {'type': 'A', 'value': '10.0.0.5'},
        {'type': 'MX', 'value': '32 mail.lan'},
      ],
    });
    expect(mixed.typeLabels, ['TXT', 'A / AAAA', 'A', 'MX']);
    expect(mixed.matches('spf1'), isTrue);
    expect(mixed.matches('nothing'), isFalse);

    final config = DesktopRewriteConfig.fromJson(const {'enabled': true});
    expect(config.effectiveTtl, desktopRewriteDefaultTtl);
    expect(config.rules, isEmpty);
    expect(
      const DesktopRewriteConfig(
        enabled: true,
        ttl: 30,
      ).copyWith(ttl: 90).effectiveTtl,
      90,
    );
  });

  testWidgets('页面显示服务返回的引擎状态、默认 TTL 与规则表', (tester) async {
    await pumpRewrite(tester);
    final l10n = l10nOf(tester);

    expect(find.byType(DesktopRewritePage), findsOneWidget);
    expect(find.text(l10n.desktopRewriteEngineTitle), findsOneWidget);
    expect(find.text(l10n.desktopRewriteEngineOn), findsOneWidget);
    expect(find.text(l10n.desktopRewriteRulesCount(5)), findsOneWidget);

    // Names, type chips, targets and the lifetimes the service reported.
    expect(find.text('host.lan'), findsOneWidget);
    expect(find.text(l10n.desktopRewriteTypeIp), findsOneWidget);
    expect(find.text('192.168.1.100 · fd00::100'), findsOneWidget);
    expect(find.text(l10n.desktopRewriteSeconds(120)), findsOneWidget);
    expect(find.text('alias.lan'), findsOneWidget);
    expect(find.text('CNAME'), findsOneWidget);
    expect(find.text('target.lan'), findsOneWidget);
    expect(find.text(l10n.desktopRewriteSeconds(60)), findsWidgets);
    expect(find.text('"v=spf1 ~all"'), findsOneWidget);
    expect(find.text('MX 32 mail.lan · A 10.0.0.5'), findsOneWidget);
    expect(find.text(l10n.desktopRewriteRcodeOnly('NXDOMAIN')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换开关提交开关值并回显服务端状态', (tester) async {
    final backend = await pumpRewrite(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inEngine(find.byType(DashboardSwitch)));

    expect(backend.rewriteConfigUpdates.single, {'enabled': false});
    expect(find.text(l10n.desktopRewriteToggleOff), findsOneWidget);
    expect(find.text(l10n.desktopRewriteEngineOff), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('默认 TTL 由保存按钮提交，非法数字不提交', (tester) async {
    final backend = await pumpRewrite(tester);
    final l10n = l10nOf(tester);

    final ttl = inEngine(find.byType(TextFormField));
    await tester.enterText(ttl, '');
    await tester.pumpAndSettle();
    await tapAt(
      tester,
      inEngine(find.widgetWithText(TonalButton, l10n.desktopRewriteTtlSave)),
    );
    expect(find.text(l10n.desktopRewriteTtlInvalid), findsOneWidget);
    expect(backend.rewriteConfigUpdates, isEmpty, reason: '空值不该发给服务');

    await tester.enterText(ttl, '300');
    await tester.pumpAndSettle();
    await tapAt(
      tester,
      inEngine(find.widgetWithText(TonalButton, l10n.desktopRewriteTtlSave)),
    );

    expect(backend.rewriteConfigUpdates.single, {'ttl': 300});
    expect(find.text(l10n.desktopRewriteTtlSaved), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('添加规则：快捷目标提交域名与地址列表', (tester) async {
    final backend = await pumpRewrite(tester);
    final l10n = l10nOf(tester);

    await tapAt(
      tester,
      find.widgetWithText(TonalButton, l10n.desktopRewriteAdd),
    );
    expect(find.text(l10n.desktopRewriteAddTitle), findsOneWidget);

    await tester.enterText(
      inDialog(
        find.widgetWithText(TextFormField, l10n.desktopRewriteDomainLabel),
      ),
      'Printer.LAN',
    );
    await tester.enterText(
      inDialog(find.widgetWithText(TextFormField, l10n.desktopRewriteIpsLabel)),
      '10.0.0.9\n10.0.0.10',
    );
    await tester.pumpAndSettle();
    await tapAt(tester, inDialog(find.text(l10n.commonSave)));

    final sent = backend.rewriteRuleUpdates.single;
    expect(sent['domain'], 'printer.lan', reason: '域名按服务规范转小写');
    expect(sent['ips'], ['10.0.0.9', '10.0.0.10']);
    expect(sent.containsKey('records'), isFalse);
    expect(
      find.text(l10n.desktopRewriteRuleSaved('printer.lan')),
      findsOneWidget,
    );
    expect(inEngine(find.text(l10n.desktopRewriteEngineOn)), findsOneWidget);
    expect(find.text('printer.lan'), findsOneWidget, reason: '保存后回读服务端列表');
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑别名规则时回填快捷字段并按修改提交', (tester) async {
    final backend = await pumpRewrite(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, find.byTooltip(l10n.desktopRewriteEdit).at(1));
    expect(find.text(l10n.desktopRewriteEditTitle), findsOneWidget);
    expect(
      inDialog(
        find.widgetWithText(TextFormField, l10n.desktopRewriteCnameLabel),
      ),
      findsOneWidget,
      reason: '带 cname 的规则打开在快捷目标模式',
    );

    await tester.enterText(
      inDialog(
        find.widgetWithText(TextFormField, l10n.desktopRewriteCnameLabel),
      ),
      'New.LAN',
    );
    await tester.pumpAndSettle();
    await tapAt(tester, inDialog(find.text(l10n.commonSave)));

    final sent = backend.rewriteRuleUpdates.single;
    expect(sent['domain'], 'alias.lan');
    expect(sent['cname'], 'new.lan');
    expect(sent.containsKey('ips'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑自定义记录规则时保留整份记录列表', (tester) async {
    final backend = await pumpRewrite(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, find.byTooltip(l10n.desktopRewriteEdit).at(3));
    // The rule carries no shortcut field, so the editor opens on its record list with both values
    // already in place.
    expect(inDialog(find.text('MX')), findsOneWidget);
    expect(inDialog(find.text('A')), findsOneWidget);
    expect(inDialog(find.text('32 mail.lan')), findsWidgets);
    expect(inDialog(find.text('10.0.0.5')), findsWidgets);

    await tapAt(tester, inDialog(find.text(l10n.commonSave)));

    final sent = backend.rewriteRuleUpdates.single;
    expect(sent['domain'], 'mail.lan');
    expect(sent['records'], [
      {'type': 'MX', 'value': '32 mail.lan'},
      {'type': 'A', 'value': '10.0.0.5'},
    ]);
    expect(sent.containsKey('ips'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('失败应答码不需要目标即可保存', (tester) async {
    final backend = await pumpRewrite(tester);
    final l10n = l10nOf(tester);

    await tapAt(
      tester,
      find.widgetWithText(TonalButton, l10n.desktopRewriteAdd),
    );
    await tester.enterText(
      inDialog(
        find.widgetWithText(TextFormField, l10n.desktopRewriteDomainLabel),
      ),
      'off.lan',
    );
    // The picker itself is a button; its menu item carries the code.
    await tapAt(tester, inDialog(find.text(l10n.desktopRewriteRcodeNone)));
    await tapAt(tester, find.text('REFUSED').last);
    expect(find.text(l10n.desktopRewriteRcodeWarning), findsOneWidget);

    await tapAt(tester, inDialog(find.text(l10n.commonSave)));

    final sent = backend.rewriteRuleUpdates.single;
    expect(sent['domain'], 'off.lan');
    expect(sent['rcode'], 'REFUSED');
    expect(sent.containsKey('ips'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('删除规则先确认再发 DELETE', (tester) async {
    final backend = await pumpRewrite(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, find.byTooltip(l10n.desktopRewriteDelete).first);
    expect(find.text(l10n.desktopRewriteDeleteTitle), findsOneWidget);
    expect(
      find.text(l10n.desktopRewriteDeleteBody('host.lan')),
      findsOneWidget,
    );
    await tapAt(tester, inDialog(find.text(l10n.desktopRewriteDelete)));

    expect(backend.rewriteDeletes, ['host.lan']);
    expect(
      find.text(l10n.desktopRewriteRuleDeleted('host.lan')),
      findsOneWidget,
    );
    expect(find.text('host.lan'), findsNothing);
    expect(find.text(l10n.desktopRewriteRulesCount(4)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('检索只收窄已返回规则，清空后恢复', (tester) async {
    final backend = await pumpRewrite(tester);
    final l10n = l10nOf(tester);

    await tester.enterText(
      find.descendant(
        of: find.byType(SearchField),
        matching: find.byType(TextField),
      ),
      'mail',
    );
    await tester.pumpAndSettle();

    expect(find.text('mail.lan'), findsOneWidget);
    expect(find.text('host.lan'), findsNothing);
    expect(find.text(l10n.desktopRewriteNoMatch), findsNothing);
    expect(
      backend.requests.where((path) => path == '/api/v1/dns/rewrite/rules'),
      hasLength(1),
      reason: '检索是本地过滤，不再请求服务',
    );

    await tapAt(tester, find.text(l10n.desktopRewriteResetSearch));
    expect(find.text('host.lan'), findsOneWidget);
    expect(find.text(l10n.desktopRewriteRulesCount(5)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有规则与检索无结果分别给出空态', (tester) async {
    await pumpRewrite(
      tester,
      backend: FakeDesktopBackend(rewrite: rewritePayload(rules: const [])),
    );
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopRewriteEmpty), findsOneWidget);
    expect(find.text(l10n.desktopRewriteRulesCount(0)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('服务拒绝写入时说明原因且开关回到服务端值', (tester) async {
    final backend = await pumpRewrite(tester);
    final l10n = l10nOf(tester);
    backend.rejectWrites = true;

    await tapAt(tester, inEngine(find.byType(DashboardSwitch)));

    expect(
      find.text(l10n.desktopRewriteSaveFailed('write rejected')),
      findsOneWidget,
    );
    expect(find.text(l10n.desktopRewriteEngineOn), findsOneWidget);
    expect(tester.takeException(), isNull);
    await clearMessages(tester);
  });

  testWidgets('重新读取失败时保留上一份并标注过期', (tester) async {
    final backend = await pumpRewrite(tester);
    final l10n = l10nOf(tester);
    backend.failAfter = 1;

    await tapAt(tester, find.byTooltip(l10n.logsRefresh));

    expect(find.byType(StaleStatusNotice), findsOneWidget);
    expect(find.text('host.lan'), findsOneWidget, reason: '旧快照仍可读');
    expect(tester.takeException(), isNull);
  });

  testWidgets('需要令牌时整页说明原因并给重试', (tester) async {
    await pumpRewrite(tester, backend: FakeDesktopBackend(statusCode: 401));
    final l10n = l10nOf(tester);

    expect(find.byType(NullStatus), findsOneWidget);
    expect(find.text(l10n.desktopRewriteLoadFailed), findsOneWidget);
    expect(find.text(l10n.desktopBackendUnauthorizedBody), findsOneWidget);
    expect(find.text(l10n.desktopRetry), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗口把表格换成三行堆叠，不裁掉域名', (tester) async {
    await pumpRewrite(tester, size: const Size(620, 900));
    final l10n = l10nOf(tester);

    // 窄卡片放不下五列，表头消失、域名整行显示，寿命并入类型徽标那一行。
    expect(find.text(l10n.desktopRewriteDomain), findsNothing);
    expect(find.text('host.lan'), findsOneWidget);
    expect(find.text(l10n.desktopRewriteSeconds(120)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('功能中心入口打开重写子页', (tester) async {
    await pumpRewrite(tester, location: '/hub');
    final l10n = tester.element(find.byType(DesktopFeatureHubPage)).l10n;

    await tapAt(tester, find.text(l10n.desktopHubRewrite));

    expect(find.byType(DesktopRewritePage), findsOneWidget);
    expect(find.text(l10n.desktopRewriteEngineTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
