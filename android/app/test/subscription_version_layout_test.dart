// U9: the subscription version page keeps its subscription list beside the history on a tablet and
// falls back to the dropdown on a phone.

import 'package:diting_android/data/db/rule_version_repository.dart';
import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/pages/hub/subscription_version_page.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_host.dart';

List<SubscriptionEntry> _entries() => [
  SubscriptionEntry(
    record: SubscriptionRecord(
      id: 1,
      url: 'https://example.com/a.txt',
      name: '订阅 A',
      sourceType: SubscriptionSourceType.remote,
      kind: SubscriptionKind.domain,
      enabled: true,
      ruleCount: 3,
      lastUpdated: 0,
      addedAt: 0,
      importState: SubscriptionImportState.ready,
      lastAttemptAt: 0,
      consecutiveFailureCount: 0,
      mirrorFallback: false,
    ),
  ),
  SubscriptionEntry(
    record: SubscriptionRecord(
      id: 2,
      url: 'https://example.com/b.txt',
      name: '订阅 B',
      sourceType: SubscriptionSourceType.remote,
      kind: SubscriptionKind.domain,
      enabled: true,
      ruleCount: 5,
      lastUpdated: 0,
      addedAt: 0,
      importState: SubscriptionImportState.ready,
      lastAttemptAt: 0,
      consecutiveFailureCount: 0,
      mirrorFallback: false,
    ),
  ),
];

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
  });
  tearDown(() async {
    await db.close();
  });

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = RuleVersionRepository(db);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionEntriesProvider.overrideWith((ref) async => _entries()),
          ruleVersionRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: AppHost(
          size: size,
          isMobile: size.width < 720,
          child: const SubscriptionVersionPage(),
        ),
      ),
    );
    // Resolve the provider futures and the history query without waiting on the loading spinner.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('平板宽度：订阅列表与版本历史并排（无选择菜单）', (tester) async {
    await pump(tester, const Size(1200, 900));

    expect(find.text('订阅 A'), findsOneWidget);
    expect(find.text('订阅 B'), findsOneWidget);
    // Two-pane keeps every subscription visible; no picker menu is needed.
    expect(find.byType(PopupSelectButton<int>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机宽度：用选择菜单且不溢出', (tester) async {
    await pump(tester, const Size(400, 800));

    expect(find.byType(PopupSelectButton<int>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏 1.4 倍字号不溢出（U8）', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, const Size(320, 700));

    expect(tester.takeException(), isNull);
  });
}
