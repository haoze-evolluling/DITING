// Desktop hub rewrite page's local authoritative zones (desktop parity): one row per zone with the
// service's build result, the RFC 1035 text edited locally, and a preview through the service's own
// parser. Only "save all" writes; a rejected save rolls back.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_zone_models.dart';
import 'package:diting_desktop/pages/hub/desktop_rewrite_page.dart';
import 'package:diting_desktop/pages/hub/widgets/zone_file_card.dart';
import 'package:diting_desktop/pages/hub/widgets/zone_settings_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';
import 'support/desktop_page_harness.dart';

void main() {
  Future<FakeDesktopBackend> pumpZones(
    WidgetTester tester, {
    FakeDesktopBackend? backend,
    Size size = const Size(1280, 900),
  }) => pumpDesktopPage(
    tester,
    path: DesktopRewritePage.path,
    backend: backend,
    size: size,
  );

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(ZoneFileCard)).l10n;

  Finder inZones(Finder matching) =>
      find.descendant(of: find.byType(ZoneFileCard), matching: matching);
  Finder inSettings(Finder matching) => find.descendant(
    of: find.byType(ZoneSettingsCard),
    matching: matching,
  );


  test('缺字段按零值解析，区状态按 id 查找', () {
    final entry = DesktopZoneEntry.fromJson(const {'id': 'z1'});
    expect(entry.origin, isEmpty);
    expect(entry.enabled, isFalse);

    final config = DesktopZoneConfig.fromJson(const {
      'enabled': true,
      'states': [
        {'id': 'z1', 'records': 3, 'loaded': true},
        {'id': 'z2', 'loaded': false, 'error': 'missing origin'},
      ],
    });
    expect(config.effectiveTtl, desktopZoneDefaultTtl);
    expect(config.maxZones, 32);
    expect(config.stateOf('z1')?.records, 3);
    expect(config.stateOf('z2')?.error, 'missing origin');
    expect(config.stateOf('gone'), isNull);
    expect(config.copyWith(ttl: 90).effectiveTtl, 90);

    final preview = DesktopZoneTest.fromJson(const {
      'success': false,
      'error': 'bad record',
    });
    expect(preview.success, isFalse);
    expect(preview.records, isEmpty);
    expect(preview.error, 'bad record');
  });

  testWidgets('卡片显示服务返回的区数量、名字数与构建结果', (tester) async {
    await pumpZones(tester);
    final l10n = l10nOf(tester);

    expect(find.byType(ZoneFileCard), findsOneWidget);
    expect(find.byType(ZoneSettingsCard), findsOneWidget);
    expect(find.text(l10n.desktopZoneTitle), findsOneWidget);
    expect(find.text(l10n.desktopZoneBadge(2, 32, 2)), findsWidgets);
    expect(find.byKey(const ValueKey('zone-lan-origin')), findsOneWidget);
    expect(find.byKey(const ValueKey('zone-intra-origin')), findsOneWidget);
    expect(find.text(l10n.desktopZoneStateLoaded(2)), findsOneWidget);
    expect(find.text(l10n.desktopZoneStateDisabled), findsOneWidget);
    expect(find.text(l10n.desktopZoneLimit(10000)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('添加区只改本地草稿，保存全部才提交整份列表', (tester) async {
    final backend = await pumpZones(tester);
    final l10n = l10nOf(tester);

    await tapAt(
      tester,
      inZones(find.widgetWithText(TonalButton, l10n.desktopZoneAdd)),
    );
    expect(backend.zoneConfigUpdates, isEmpty, reason: '新增只改本地草稿');

    await tapAt(
      tester,
      inZones(find.widgetWithText(TonalButton, l10n.desktopZoneSaveAll)),
    );

    final zones = backend.zoneConfigUpdates.single['zones'] as List<Object?>;
    expect(zones, hasLength(3));
    final added = (zones.last as Map).cast<String, Object?>();
    expect(added['origin'], isEmpty);
    expect(added['enabled'], isTrue);
    expect('${added['content']}', contains(r'$ORIGIN example.lan.'));
    expect(find.text(l10n.desktopZoneSaved), findsOneWidget);
    expect(find.text('missing origin'), findsOneWidget, reason: '服务端逐区状态原样显示');
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑顶点与区文本后保存全部', (tester) async {
    final backend = await pumpZones(tester);
    final l10n = l10nOf(tester);

    await tester.enterText(
      find.byKey(const ValueKey('zone-intra-origin')),
      'intra.lan.',
    );
    await tester.pumpAndSettle();
    await tapAt(tester, find.byTooltip(l10n.desktopZoneExpand).at(1));
    await tester.enterText(
      find.byKey(const ValueKey('zone-intra-content')),
      '\$ORIGIN intra.lan.\nwww IN A 10.0.0.2\n',
    );
    await tester.pumpAndSettle();
    await tapAt(
      tester,
      inZones(find.widgetWithText(TonalButton, l10n.desktopZoneSaveAll)),
    );

    final zones = backend.zoneConfigUpdates.single['zones'] as List<Object?>;
    final edited = (zones[1] as Map).cast<String, Object?>();
    expect(edited['origin'], 'intra.lan.');
    expect('${edited['content']}', contains('www IN A 10.0.0.2'));
    expect(edited['enabled'], isFalse, reason: '未改动的开关原样提交');
    expect(find.text(l10n.desktopZoneSaved), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('删除区立即提交并在失败时回滚', (tester) async {
    final backend = await pumpZones(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inZones(find.byTooltip(l10n.desktopZoneDelete)).first);

    final zones = backend.zoneConfigUpdates.single['zones'] as List<Object?>;
    expect(zones, hasLength(1));
    expect(find.text(l10n.desktopZoneDeleted('lan.')), findsOneWidget);
    expect(find.byKey(const ValueKey('zone-lan-origin')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    backend.rejectWrites = true;
    await tapAt(tester, inZones(find.byTooltip(l10n.desktopZoneDelete)).first);

    expect(
      find.text(l10n.desktopZoneSaveFailed('write rejected')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('zone-intra-origin')),
      findsOneWidget,
      reason: '被拒后恢复服务端仍持有的区',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('默认 TTL 提交数字，非法值不提交', (tester) async {
    final backend = await pumpZones(tester);
    final l10n = l10nOf(tester);

    final ttl = inSettings(
      find.widgetWithText(TextFormField, l10n.desktopZoneDefaultTtl),
    );
    await tester.enterText(ttl, '');
    await tester.pumpAndSettle();
    await tapAt(
      tester,
      inSettings(find.widgetWithText(TonalButton, l10n.commonSave)),
    );
    expect(find.text(l10n.desktopZoneTtlInvalid), findsOneWidget);
    expect(backend.zoneConfigUpdates, isEmpty, reason: '空值不该发给服务');

    await tester.enterText(ttl, '600');
    await tester.pumpAndSettle();
    await tapAt(
      tester,
      inSettings(find.widgetWithText(TonalButton, l10n.commonSave)),
    );

    expect(backend.zoneConfigUpdates.single, {'ttl': 600});
    expect(find.text(l10n.desktopZoneTtlSaved), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('区引擎开关与整表开关各自提交一个字段', (tester) async {
    final backend = await pumpZones(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inSettings(find.byType(DashboardSwitch)));

    expect(backend.zoneConfigUpdates.single, {'enabled': false});
    expect(find.text(l10n.desktopZoneToggleOff), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('预演解析把文本交给服务并显示记录或失败原因', (tester) async {
    final backend = await pumpZones(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, find.byTooltip(l10n.desktopZoneExpand).first);
    await tapAt(
      tester,
      inZones(find.widgetWithText(TonalButton, l10n.desktopZonePreview)),
    );

    final sent = backend.zoneTests.single;
    expect(sent['origin'], 'lan.');
    expect(sent['ttl'], desktopZoneDefaultTtl);
    expect('${sent['content']}', contains('www IN A 192.168.1.10'));
    expect(find.text('www.lan. 300 IN A 192.168.1.10'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    backend.zoneTest = zoneTestPayload(
      success: false,
      error: 'line 2: bad record',
    );
    await tapAt(
      tester,
      inZones(find.widgetWithText(TonalButton, l10n.desktopZonePreview)),
    );
    expect(find.text('line 2: bad record'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗口把状态徽标移到下一行且不溢出', (tester) async {
    await pumpZones(tester, size: const Size(720, 900));
    final l10n = l10nOf(tester);

    expect(find.byKey(const ValueKey('zone-lan-origin')), findsOneWidget);
    expect(find.text(l10n.desktopZoneStateLoaded(2)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
