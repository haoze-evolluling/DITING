import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/pages/subscriptions/subscriptions_page.dart';
import 'package:diting_android/state/deep_link_providers.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support/app_host.dart';

class _SeededImportNotifier extends PendingSubscriptionImportNotifier {
  @override
  String? build() => 'https://example.com/rules.txt';
}

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    List<SubscriptionEntry> entries = const [],
    List<Override> extraOverrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionEntriesProvider.overrideWith((ref) async => entries),
          subscriptionGroupsProvider.overrideWith((ref) async => const []),
          mirrorTemplatesProvider.overrideWith((ref) async => const []),
          ...extraOverrides,
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

  testWidgets('深链待导入地址会自动预填到新增表单', (tester) async {
    await pumpPage(
      tester,
      extraOverrides: [
        pendingSubscriptionImportProvider.overrideWith(_SeededImportNotifier.new),
      ],
    );

    expect(find.text('https://example.com/rules.txt'), findsWidgets);
  });
}
