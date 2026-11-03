// Desktop hub app blocking (desktop parity): the built-in catalogue,
// the selection, group blocking and the per-service weekly plan. Every value must come from
// `/filter/services`; each write adopts the whole state the service answers with.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_services_models.dart';
import 'package:diting_desktop/pages/hub/desktop_services_page.dart';
import 'package:diting_desktop/pages/hub/widgets/blocked_services_card.dart';
import 'package:diting_desktop/pages/hub/widgets/blocked_services_groups_card.dart';
import 'package:diting_desktop/pages/hub/widgets/schedule_editor.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';
import 'support/desktop_page_harness.dart';

void main() {
  Future<FakeDesktopBackend> pumpServices(
    WidgetTester tester, {
    FakeDesktopBackend? backend,
    Size size = const Size(1280, 900),
  }) => pumpDesktopPage(
    tester,
    path: DesktopServicesPage.path,
    backend: backend,
    size: size,
  );

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopServicesPage)).l10n;

  Finder inCard(Finder matching) =>
      find.descendant(of: find.byType(BlockedServicesCard), matching: matching);
  Finder inGroups(Finder matching) => find.descendant(
    of: find.byType(BlockedServiceGroupsCard),
    matching: matching,
  );



  test('缺字段按零值解析，随分组与计划状态可查询', () {
    final data = DesktopBlockedServices.fromJson(const {
      'services': [
        {'id': 'a', 'group': 'social', 'rules': ['||a.com^']},
        {'id': 'b', 'group': 'video'},
      ],
      'groups': [
        {'id': 'social', 'name': '社交', 'count': 1},
      ],
      'blockedIds': ['b'],
      'blockedGroups': ['social'],
      'scheduleStates': [
        {'serviceId': 'a', 'hasSchedule': true, 'active': false},
      ],
    });
    expect(data.services, hasLength(2));
    expect(data.blockedCount, 2, reason: 'a 随分组、b 单独勾选');
    expect(data.blockedByGroup(data.services.first), isTrue);
    expect(data.isBlocked(data.services.last), isTrue);
    expect(data.groupName('social'), '社交');
    expect(data.groupName('missing'), 'missing');
    expect(data.stateOf('a')?.hasSchedule, isTrue);
    expect(data.stateOf('a')?.active, isFalse);
    expect(data.schedulesOf('a'), isEmpty);
    expect(DesktopBlockedServices.fromJson(const {}).blockedCount, 0);
  });

  testWidgets('页面显示目录、分组与已拦截数量', (tester) async {
    await pumpServices(tester);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopServicesTitle), findsOneWidget);
    expect(find.text(l10n.desktopServicesCount(1, 2)), findsOneWidget);
    expect(find.text('抖音'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text(l10n.desktopServicesRuleCount('社交', 1)), findsOneWidget);
    expect(
      find.text(l10n.desktopServicesGroupChip('视频', 1)),
      findsOneWidget,
    );
    expect(find.text(l10n.desktopServicesActiveRules(2)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换单个服务提交整份选择并回显', (tester) async {
    final backend = await pumpServices(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inCard(find.byType(DashboardSwitch)).first);

    final update = backend.servicesUpdates.single;
    expect(update['ids'], ['youtube', 'douyin']);
    expect(update['groups'], isEmpty);
    expect(find.text(l10n.desktopServicesBlocked('抖音')), findsOneWidget);
    expect(find.text(l10n.desktopServicesCount(2, 2)), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('整组拦截会清掉组内单独勾选的服务', (tester) async {
    final backend = await pumpServices(
      tester,
      backend: FakeDesktopBackend(
        services: servicesPayload(
          blockedIds: const ['douyin'],
          blockedGroups: const [],
        ),
      ),
    );
    final l10n = l10nOf(tester);

    await tapAt(tester, find.text(l10n.desktopServicesGroupChip('社交', 1)));

    final update = backend.servicesUpdates.single;
    expect(update['groups'], ['social']);
    expect(update['ids'], isEmpty, reason: '组内单独勾选被整组取代');
    expect(find.text(l10n.desktopServicesByGroup), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('全部取消提交空选择', (tester) async {
    final backend = await pumpServices(tester);
    final l10n = l10nOf(tester);

    await tapAt(
      tester,
      inGroups(find.byTooltip(l10n.desktopServicesClearAll)),
    );

    final update = backend.servicesUpdates.single;
    expect(update['ids'], isEmpty);
    expect(update['groups'], isEmpty);
    expect(find.text(l10n.desktopServicesCount(0, 2)), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('检索按名称与规则收窄已返回的服务', (tester) async {
    final backend = await pumpServices(tester);
    final l10n = l10nOf(tester);

    await tester.enterText(inCard(find.byType(TextField)), 'ytimg');
    await tester.pumpAndSettle();

    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('抖音'), findsNothing);
    expect(backend.servicesUpdates, isEmpty, reason: '检索不重发请求');

    await tester.enterText(inCard(find.byType(TextField)), 'nothing');
    await tester.pumpAndSettle();
    expect(find.text(l10n.desktopServicesNoMatch), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('展开显示服务规则', (tester) async {
    await pumpServices(tester);
    final l10n = l10nOf(tester);

    await tapAt(
      tester,
      inCard(find.byTooltip(l10n.desktopServicesShowRules)).first,
    );
    expect(find.text('||douyin.com^'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('每周计划保存后提交到该服务并显示计划内', (tester) async {
    final backend = await pumpServices(tester);
    final l10n = l10nOf(tester);

    await tapAt(
      tester,
      inCard(find.byTooltip(l10n.desktopServicesScheduleEdit)).first,
    );
    expect(find.byType(ScheduleEditor), findsOneWidget);
    await tapAt(tester, find.text(l10n.desktopScheduleAdd));

    final fields = find.descendant(
      of: find.byType(ScheduleEditor),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(0), '仅夜间');
    await tester.enterText(fields.at(1), '20:00');
    await tester.enterText(fields.at(2), '23:00');
    await tapAt(tester, find.text(l10n.desktopServicesScheduleSave));

    final update = backend.servicesUpdates.single;
    final schedules = update['schedules'] as Map;
    expect(schedules.keys, ['douyin']);
    expect((schedules['douyin'] as List).single, {
      'id': '',
      'name': '仅夜间',
      'enabled': true,
      'weekdays': <String>[],
      'start': '20:00',
      'end': '23:00',
    });
    expect(find.text(l10n.desktopServicesScheduleInside), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('写被拒时说明原因且选择保持服务端状态', (tester) async {
    final backend = await pumpServices(tester);
    final l10n = l10nOf(tester);
    backend.rejectWrites = true;

    await tapAt(tester, inCard(find.byType(DashboardSwitch)).first);

    expect(
      find.text(l10n.desktopServicesActionFailed('write rejected')),
      findsOneWidget,
    );
    expect(find.text(l10n.desktopServicesCount(1, 2)), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗下服务卡片单列且不横向溢出', (tester) async {
    await pumpServices(tester, size: const Size(390, 844));
    expect(find.byType(BlockedServicesCard), findsOneWidget);
    expect(find.byType(BlockedServiceGroupsCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
