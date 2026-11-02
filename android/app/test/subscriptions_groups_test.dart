// 分组管理入口回归：用户反馈新建分组后找不到重命名/删除入口，因此入口必须常驻在分组筛选行右侧。
import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/pages/subscriptions/subscriptions_page.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_host.dart';

void main() {
  testWidgets('分组管理入口可见并能打开重命名/删除', (tester) async {
    const group = SubscriptionGroupRecord(
      id: 7,
      name: '常用规则',
      autoUpdateEnabled: true,
      addedAt: 1,
    );
    final entry = SubscriptionEntry(
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
        groupId: group.id,
      ),
      groupName: group.name,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionEntriesProvider.overrideWith((ref) async => [entry]),
          subscriptionGroupsProvider.overrideWith((ref) async => [group]),
        ],
        child: const AppHost(child: SubscriptionsPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 入口固定在筛选行右侧，不随分组 chips 滚动隐藏。
    expect(find.text('管理分组'), findsOneWidget);
    await tester.tap(find.text('管理分组'));
    await tester.pumpAndSettle();

    expect(find.text('分组管理'), findsOneWidget);
    expect(find.text('1 个订阅'), findsOneWidget);
    expect(find.byTooltip('编辑'), findsOneWidget);
    expect(find.byTooltip('删除'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
