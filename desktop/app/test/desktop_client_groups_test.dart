// Desktop traffic branch, client groups (desktop parity):
// `/clients/groups` is one document, edited as drafts and written once.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_client_groups_models.dart';
import 'package:diting_desktop/pages/traffic/desktop_client_groups_page.dart';
import 'package:diting_desktop/pages/traffic/widgets/client_group_editor.dart';
import 'package:diting_desktop/pages/traffic/widgets/client_groups_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';
import 'support/desktop_page_harness.dart';

void main() {
  Future<FakeDesktopBackend> pumpGroups(
    WidgetTester tester, {
    FakeDesktopBackend? backend,
    Size size = const Size(1280, 900),
  }) => pumpDesktopPage(
    tester,
    path: DesktopClientGroupsPage.path,
    backend: backend,
    size: size,
  );

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopClientGroupsPage)).l10n;

  Finder inCard(Finder matching) =>
      find.descendant(of: find.byType(ClientGroupsCard), matching: matching);
  Finder inEditor(Finder matching) => find.descendant(
    of: find.byType(ClientGroupEditor),
    matching: matching,
  );



  test('缺字段按零值解析，空绑定列表表示继承', () {
    final group = DesktopClientGroup.fromJson(const {});
    expect(group.id, isEmpty);
    expect(group.enabled, isFalse);
    expect(group.clients, isEmpty);
    expect(group.ruleListIds, isEmpty);
    expect(group.blockMode, isEmpty);

    final data = DesktopClientGroups.fromJson(const {
      'enabled': true,
      'groups': [
        {'id': 'g1', 'clients': ['10.0.0.0/8']},
      ],
    });
    expect(data.enabled, isTrue);
    expect(data.groups.single.clients, ['10.0.0.0/8']);
    expect(data.ruleLists, isEmpty);
    expect(data.upstreams, isEmpty);

    // Empty bindings are omitted so the service keeps its inherit semantics.
    final json = group.toJson();
    expect(json.containsKey('ruleListIds'), isFalse);
    expect(json.containsKey('upstreamIds'), isFalse);
  });

  testWidgets('分组编辑器显示成员、拦截方式、计划与绑定项', (tester) async {
    await pumpGroups(tester);
    final l10n = l10nOf(tester);

    expect(find.text('儿童设备'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(inEditor(find.byType(TextField)).at(1))
          .controller
          ?.text,
      '192.168.1.30',
    );
    expect(find.text(l10n.desktopGroupsModeNxdomain), findsOneWidget);
    expect(find.text('晚间'), findsOneWidget);
    expect(find.text('广告拦截'), findsOneWidget);
    expect(find.text('up1'), findsOneWidget);
    expect(find.text(l10n.desktopGroupsCount(1, 1)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('改名与改成员后保存提交整份分组', (tester) async {
    final backend = await pumpGroups(tester);
    final l10n = l10nOf(tester);

    await tester.enterText(inEditor(find.byType(TextFormField)).first, '书房');
    await tester.enterText(
      inEditor(find.byType(TextField)).at(1),
      '192.168.1.30\n192.168.1.31\n',
    );
    await tapAt(tester, inCard(find.byTooltip(l10n.desktopGroupsSave)));

    final body = backend.groupsUpdates.single;
    expect(body['enabled'], isTrue);
    final group = (body['groups'] as List).single as Map;
    expect(group['name'], '书房');
    expect(group['clients'], ['192.168.1.30', '192.168.1.31']);
    expect(group['blockMode'], 'nxdomain');
    expect(find.text(l10n.desktopGroupsSaved), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有成员的分组不会提交', (tester) async {
    final backend = await pumpGroups(tester);
    final l10n = l10nOf(tester);

    await tester.enterText(inEditor(find.byType(TextField)).at(1), '  ');
    await tapAt(tester, inCard(find.byTooltip(l10n.desktopGroupsSave)));

    expect((backend.groupsUpdates.single['groups'] as List), isEmpty);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新增与删除分组都进入同一次保存', (tester) async {
    final backend = await pumpGroups(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inCard(find.text(l10n.desktopGroupsAdd)));
    expect(find.byType(ClientGroupEditor), findsNWidgets(2));

    await tapAt(tester, inEditor(find.byType(DashboardIconButton)).first);
    expect(find.text(l10n.desktopGroupsDeleteTitle), findsOneWidget);
    await tapAt(tester, find.text(l10n.desktopGroupsDelete));
    expect(find.byType(ClientGroupEditor), findsOneWidget);
    expect(find.text('儿童设备'), findsNothing);

    await tapAt(tester, inCard(find.byTooltip(l10n.desktopGroupsSave)));
    expect((backend.groupsUpdates.single['groups'] as List), isEmpty);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关闭总开关后保存，分组列表仍原样提交', (tester) async {
    final backend = await pumpGroups(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inCard(find.byType(DashboardSwitch)).first);
    expect(find.byType(ClientGroupEditor), findsNothing);
    await tapAt(tester, inCard(find.byTooltip(l10n.desktopGroupsSave)));

    final body = backend.groupsUpdates.single;
    expect(body['enabled'], isFalse);
    expect(body['groups'], hasLength(1));
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('写被拒时说明原因并保留草稿', (tester) async {
    final backend = FakeDesktopBackend()..rejectWrites = true;
    await pumpGroups(tester, backend: backend);
    final l10n = l10nOf(tester);

    await tester.enterText(inEditor(find.byType(TextFormField)).first, '书房');
    await tapAt(tester, inCard(find.byTooltip(l10n.desktopGroupsSave)));
    expect(
      find.text(l10n.desktopTrafficSaveFailed('write rejected')),
      findsOneWidget,
    );
    expect(find.text('书房'), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗单列且不横向溢出', (tester) async {
    await pumpGroups(tester, size: const Size(390, 844));
    expect(find.byType(ClientGroupsCard), findsOneWidget);
    expect(find.byType(ClientGroupEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
