// 本地 TXT 订阅入口回归：「订阅方式」行在一次界面重做里被整行删掉，于是新建订阅只能填网络
// 地址，本地文件订阅再也建不出来。这里守住「新增可选本地文件、编辑不可改订阅方式」。
import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/pages/subscriptions/subscriptions_page.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_host.dart';

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    List<SubscriptionEntry> entries = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionEntriesProvider.overrideWith((ref) async => entries),
          subscriptionGroupsProvider.overrideWith((ref) async => const []),
          mirrorTemplatesProvider.overrideWith((ref) async => const []),
        ],
        child: const AppHost(child: SubscriptionsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  SubscriptionEntry remoteEntry() => SubscriptionEntry(
    record: SubscriptionRecord(
      id: 3,
      url: 'https://example.com/rules.txt',
      name: '示例订阅',
      sourceType: SubscriptionSourceType.remote,
      kind: SubscriptionKind.domain,
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

  testWidgets('新增订阅可以切换到本地文件', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byTooltip('添加订阅').first);
    await tester.pumpAndSettle();

    expect(find.text('订阅方式'), findsOneWidget);
    expect(find.text('订阅地址'), findsOneWidget);

    // 整行可点，菜单里选「本地文件」后地址框换成选文件行。
    await tester.tap(find.text('订阅方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本地文件'));
    await tester.pumpAndSettle();

    expect(find.text('订阅地址'), findsNothing);
    expect(find.text('选择规则文件'), findsOneWidget);
  });

  testWidgets('编辑订阅不提供订阅方式', (tester) async {
    await pumpPage(tester, entries: [remoteEntry()]);
    await tester.tap(find.byTooltip('更多').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑订阅'));
    await tester.pumpAndSettle();

    expect(find.text('编辑订阅'), findsOneWidget);
    expect(find.text('订阅地址'), findsOneWidget);
    expect(find.text('订阅方式'), findsNothing);
  });
}
