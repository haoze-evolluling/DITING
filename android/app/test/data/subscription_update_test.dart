// 更新流程的收尾保证：任何一次更新结束后，忙碌标记必须复位，列表必须重新读库，
// 否则页面会一直停在“正在更新”且卡片数据不刷新，所有入口又都因 busy 被禁用。

import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/data/db/subscription_repository.dart';
import 'package:diting_android/data/subscriptions/subscription_fetcher.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE subscription ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'url TEXT NOT NULL, '
      'name TEXT NOT NULL, '
      'sourceType TEXT NOT NULL, '
      'kind TEXT NOT NULL, '
      'enabled INTEGER NOT NULL, '
      'ruleCount INTEGER NOT NULL, '
      'lastUpdated INTEGER NOT NULL, '
      'addedAt INTEGER NOT NULL, '
      'importState TEXT NOT NULL, '
      'importError TEXT, '
      'httpEtag TEXT, '
      'httpLastModified TEXT, '
      'ruleSetHash TEXT, '
      'lastAttemptAt INTEGER NOT NULL, '
      'consecutiveFailureCount INTEGER NOT NULL, '
      'mirrorTemplate TEXT, '
      'mirrorFallback INTEGER NOT NULL, '
      'groupId INTEGER)',
    );
    await db.execute(
      'CREATE TABLE subscription_group ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'name TEXT NOT NULL, '
      'autoUpdateEnabled INTEGER NOT NULL, '
      'addedAt INTEGER NOT NULL)',
    );
  });

  tearDown(() => db.close());

  Future<int> insertRemote(ProviderContainer container) async {
    final repository = await container.read(
      subscriptionRepositoryProvider.future,
    );
    return repository!.insert(
      SubscriptionRecord(
        id: 0,
        url: 'https://example.com/rules.txt',
        name: '示例订阅',
        sourceType: SubscriptionSourceType.remote,
        kind: SubscriptionKind.domain,
        enabled: true,
        ruleCount: 0,
        lastUpdated: 0,
        addedAt: 1,
        importState: SubscriptionImportState.ready,
        lastAttemptAt: 0,
        consecutiveFailureCount: 0,
        mirrorFallback: true,
      ),
    );
  }

  test('下载抛异常时更新结束，忙碌标记复位并记下失败', () async {
    final container = ProviderContainer(
      overrides: [
        subscriptionDatabaseProvider.overrideWith((ref) async => db),
        subscriptionFetcherProvider.overrideWithValue(_ThrowingFetcher()),
      ],
    );
    addTearDown(container.dispose);
    final id = await insertRemote(container);

    final result = await container
        .read(subscriptionUpdateProvider.notifier)
        .updateOne(id);

    final state = container.read(subscriptionUpdateProvider);
    expect(result?.isFailure, isTrue);
    expect(state.isBusy, isFalse);
    expect(state.updatingIds, isEmpty);
    expect(state.lastMessage, isNotNull);
  });

  test('更新结束后列表重新读库，不依赖仓储的写回调', () async {
    final container = ProviderContainer(
      overrides: [
        subscriptionDatabaseProvider.overrideWith((ref) async => db),
        // 没有 onChanged 钩子：写入不会通知列表，只能靠更新流程自己收尾。
        subscriptionRepositoryProvider.overrideWith(
          (ref) async => SubscriptionRepository(db),
        ),
        subscriptionFetcherProvider.overrideWithValue(_NotModifiedFetcher()),
      ],
    );
    addTearDown(container.dispose);
    final id = await insertRemote(container);
    final before = await container.read(subscriptionEntriesProvider.future);
    expect(before.single.lastAttemptAt, 0);

    await container.read(subscriptionUpdateProvider.notifier).updateOne(id);

    final after = await container.read(subscriptionEntriesProvider.future);
    expect(after.single.lastAttemptAt, greaterThan(0));
    expect(container.read(subscriptionUpdateProvider).isBusy, isFalse);
  });
}

class _ThrowingFetcher implements SubscriptionFetcher {
  @override
  Future<SubscriptionFetchResult> fetch(
    SubscriptionRecord record, {
    bool useValidators = true,
  }) async {
    throw StateError('boom');
  }
}

class _NotModifiedFetcher implements SubscriptionFetcher {
  @override
  Future<SubscriptionFetchResult> fetch(
    SubscriptionRecord record, {
    bool useValidators = true,
  }) async => const SubscriptionFetchResult.notModified();
}
