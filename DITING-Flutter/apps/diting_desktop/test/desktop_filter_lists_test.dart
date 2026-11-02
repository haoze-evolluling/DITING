// Desktop hub subscription lists (desktop parity): the counters, the
// per-list health and the four writes. Every value must come from `/filter/stats` and
// `/filter/lists`; each write re-reads both, and a rejected write is reported instead of assumed.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/app/desktop_app.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_filter_models.dart';
import 'package:diting_desktop/data/api/desktop_live_providers.dart';
import 'package:diting_desktop/pages/hub/desktop_filter_lists_page.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_lists_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  Future<FakeDesktopBackend> pumpLists(
    WidgetTester tester, {
    FakeDesktopBackend? backend,
    Size size = const Size(1280, 900),
  }) async {
    final fake = backend ?? FakeDesktopBackend();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(MemoryLegacyPrefsStore()),
          desktopPollingEnabledProvider.overrideWithValue(false),
          desktopLiveEnabledProvider.overrideWithValue(false),
          desktopApiClientProvider.overrideWithValue(fake.client()),
        ],
        child: const DesktopApp(initialLocation: DesktopFilterListsPage.path),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopFilterListsPage)).l10n;

  Finder inCard(Finder matching) =>
      find.descendant(of: find.byType(FilterListsCard), matching: matching);

  Finder inDialog(Finder matching) =>
      find.descendant(of: find.byType(CommonDialog), matching: matching);

  Future<void> tapAt(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(
      tester.element(finder),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> clearMessages(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  test('缺字段按零值解析，未更新时间保持空', () {
    final list = DesktopFilterList.fromJson(const {'id': 'l1'});
    expect(list.name, isEmpty);
    expect(list.enabled, isFalse);
    expect(list.rulesCount, 0);
    expect(list.lastUpdated, isNull);
    expect(list.copyWith(enabled: true).toJson(), {
      'id': 'l1',
      'name': '',
      'url': '',
      'enabled': true,
    });

    final lists = DesktopFilterLists.fromJson(const {
      'total': 1,
      'lists': [
        {'id': 'l1', 'lastUpdated': 1700000000000, 'lastStatus': 'ok'},
      ],
    });
    expect(lists.total, 1);
    expect(lists.lists.single.lastUpdated, isNotNull);
    expect(DesktopFilterSummary.fromJson(const {}).blockRate, 0);
    expect(DesktopFilterSummary.fromJson(const {}).scheduleActive, isTrue);
  });

  testWidgets('页面显示服务返回的计数与规则库', (tester) async {
    await pumpLists(tester);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopFilterSummaryTitle), findsOneWidget);
    expect(find.text('987'), findsOneWidget);
    expect(find.text('8.0'), findsOneWidget);
    expect(find.text('2,048'), findsOneWidget);
    expect(find.text('广告拦截通用规则'), findsOneWidget);
    expect(find.text('https://example.com/ads.txt'), findsOneWidget);
    expect(find.text(l10n.desktopFilterListRules(1200)), findsOneWidget);
    expect(find.text(l10n.desktopFilterListHealthOk), findsOneWidget);
    expect(find.text(l10n.desktopFilterListHealthCached), findsOneWidget);
    expect(find.text('connection refused'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换规则库开关提交整条记录并回显服务端值', (tester) async {
    final backend = await pumpLists(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inCard(find.byType(DashboardSwitch)).first);

    final update = backend.filterListUpdates.single;
    expect(update['id'], 'list-1');
    expect(update['enabled'], isFalse);
    expect(update['url'], 'https://example.com/ads.txt', reason: '整条记录原样带上');
    expect(
      find.text(l10n.desktopFilterListToggleOff('广告拦截通用规则')),
      findsOneWidget,
    );
    final toggle = tester.widget<DashboardSwitch>(
      inCard(find.byType(DashboardSwitch)).first,
    );
    expect(toggle.value, isFalse);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单个更新与全部更新发出正确的 id', (tester) async {
    final backend = await pumpLists(tester);
    final l10n = l10nOf(tester);

    await tapAt(
      tester,
      inCard(find.byTooltip(l10n.desktopFilterListRefreshOne)).first,
    );
    expect(backend.filterListRefreshes, ['list-1']);
    expect(find.text(l10n.desktopFilterListUpdated), findsOneWidget);
    await clearMessages(tester);

    await tapAt(
      tester,
      inCard(find.byTooltip(l10n.desktopFilterListUpdateAll)),
    );
    expect(backend.filterListRefreshes, ['list-1', '']);
    expect(find.text(l10n.desktopFilterListAllUpdated), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('添加规则库先校验 URL，再提交名称与地址', (tester) async {
    final backend = await pumpLists(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inCard(find.byTooltip(l10n.desktopFilterListAdd)));
    expect(find.text(l10n.desktopFilterListAddTitle), findsOneWidget);

    await tapAt(tester, find.text(l10n.desktopFilterListAddConfirm));
    expect(find.text(l10n.desktopFilterListNeedUrl), findsOneWidget);
    expect(backend.filterListAdds, isEmpty);

    final fields = find.descendant(
      of: find.byType(CommonDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(0), '自定义规则库');
    await tester.enterText(fields.at(1), ' https://example.com/new.txt ');
    await tapAt(tester, find.text(l10n.desktopFilterListAddConfirm));

    final add = backend.filterListAdds.single;
    expect(add['name'], '自定义规则库');
    expect(add['url'], 'https://example.com/new.txt');
    expect(add['enabled'], isTrue);
    expect(find.text(l10n.desktopFilterListAdded), findsOneWidget);
    expect(find.text('自定义规则库'), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('名称留空时按位置命名', (tester) async {
    final backend = await pumpLists(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inCard(find.byTooltip(l10n.desktopFilterListAdd)));
    final fields = find.descendant(
      of: find.byType(CommonDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(1), 'https://example.com/new.txt');
    await tapAt(tester, find.text(l10n.desktopFilterListAddConfirm));

    expect(
      backend.filterListAdds.single['name'],
      l10n.desktopFilterListDefaultName(3),
    );
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('删除先确认再发请求，取消则不发', (tester) async {
    final backend = await pumpLists(tester);
    final l10n = l10nOf(tester);

    await tapAt(
      tester,
      inCard(find.byTooltip(l10n.desktopFilterListDelete)).first,
    );
    expect(find.text(l10n.desktopFilterListDeleteTitle), findsOneWidget);
    await tapAt(tester, inDialog(find.text(l10n.commonCancel)));
    expect(backend.filterListDeletes, isEmpty);

    await tapAt(
      tester,
      inCard(find.byTooltip(l10n.desktopFilterListDelete)).first,
    );
    await tapAt(
      tester,
      inDialog(find.text(l10n.desktopFilterListDeleteConfirm)),
    );
    expect(backend.filterListDeletes, ['list-1']);
    expect(find.text('广告拦截通用规则'), findsNothing);
    expect(find.text(l10n.desktopFilterListDeleted), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('写被拒时说明原因且开关保持服务端值', (tester) async {
    final backend = await pumpLists(tester);
    final l10n = l10nOf(tester);
    backend.rejectWrites = true;

    await tapAt(tester, inCard(find.byType(DashboardSwitch)).first);

    expect(
      find.text(l10n.desktopFilterActionFailed('write rejected')),
      findsOneWidget,
    );
    final toggle = tester.widget<DashboardSwitch>(
      inCard(find.byType(DashboardSwitch)).first,
    );
    expect(toggle.value, isTrue);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空列表显示空态与添加按钮', (tester) async {
    await pumpLists(
      tester,
      backend: FakeDesktopBackend(
        filterLists: filterListsPayload(lists: const []),
      ),
    );
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopFilterListsEmpty), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FilterListsCard),
        matching: find.text(l10n.desktopFilterListAdd),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗下规则库卡片不横向溢出', (tester) async {
    await pumpLists(tester, size: const Size(390, 844));
    expect(find.byType(FilterListsCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
