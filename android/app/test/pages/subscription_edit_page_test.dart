import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/pages/subscriptions/subscription_edit_page.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_host.dart';

SubscriptionEntry entry({
  int id = 3,
  String url = 'https://example.com/rules.txt',
  String name = '示例订阅',
  SubscriptionKind kind = SubscriptionKind.domain,
}) => SubscriptionEntry(
  record: SubscriptionRecord(
    id: id,
    url: url,
    name: name,
    sourceType: SubscriptionSourceType.remote,
    kind: kind,
    enabled: true,
    ruleCount: 12,
    lastUpdated: 0,
    addedAt: 1,
    importState: SubscriptionImportState.ready,
    lastAttemptAt: 0,
    consecutiveFailureCount: 0,
    mirrorFallback: true,
  ),
);

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    Widget page = const SubscriptionEditPage(),
    List<SubscriptionEntry> entries = const [],
    List<SubscriptionEntry> otherModeEntries = const [],
    List<Override> extraOverrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionEntriesProvider.overrideWith((ref) async => entries),
          subscriptionGroupsProvider.overrideWith((ref) async => const []),
          mirrorTemplatesProvider.overrideWith((ref) async => const []),
          otherModeSubscriptionsProvider.overrideWith(
            (ref) async => otherModeEntries,
          ),
          ...extraOverrides,
        ],
        child: AppHost(child: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('新增订阅可以在三种订阅方式之间切换', (tester) async {
    await pumpPage(tester);

    expect(find.text('订阅地址'), findsOneWidget);

    await tester.tap(find.text('本地文件'));
    await tester.pumpAndSettle();

    expect(find.text('订阅地址'), findsNothing);
    expect(find.text('选择规则文件'), findsOneWidget);

    await tester.tap(find.text('其他模式'));
    await tester.pumpAndSettle();

    expect(find.text('选择规则文件'), findsNothing);
    expect(find.text('订阅列表'), findsOneWidget);
  });

  testWidgets('编辑订阅不提供订阅方式选择', (tester) async {
    await pumpPage(
      tester,
      page: const SubscriptionEditPage(subscriptionId: 3),
      entries: [entry()],
    );

    expect(find.text('编辑订阅'), findsOneWidget);
    expect(find.text('订阅地址'), findsOneWidget);
    expect(find.text('网络订阅'), findsNothing);
  });

  testWidgets('深链待导入地址会自动预填到新增表单', (tester) async {
    await pumpPage(
      tester,
      page: const SubscriptionEditPage(
        prefillUrl: 'https://example.com/rules.txt',
      ),
    );

    expect(find.text('https://example.com/rules.txt'), findsWidgets);
  });

  testWidgets('其他模式列表支持勾选并标记已存在的订阅', (tester) async {
    final current = entry();
    await pumpPage(
      tester,
      entries: [current],
      otherModeEntries: [
        current,
        entry(id: 4, url: 'https://example.com/other.txt', name: '其他订阅'),
      ],
    );

    await tester.tap(find.text('其他模式'));
    await tester.pumpAndSettle();

    expect(find.text('其他订阅'), findsOneWidget);
    expect(find.text('已存在'), findsOneWidget);
    expect(find.text('已选择 0 条'), findsOneWidget);

    await tester.tap(find.text('其他订阅'));
    await tester.pumpAndSettle();

    expect(find.text('已选择 1 条'), findsOneWidget);
  });
}
