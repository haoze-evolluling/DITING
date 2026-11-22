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

  test('超大订阅在确认框拒绝后跳过导入，不写规则也不标记失败', () async {
    final container = ProviderContainer(
      overrides: [
        subscriptionDatabaseProvider.overrideWith((ref) async => db),
        subscriptionFetcherProvider.overrideWithValue(_LargeContentFetcher()),
      ],
    );
    addTearDown(container.dispose);
    final id = await insertRemote(container);

    var asked = 0;
    final result = await container
        .read(subscriptionUpdateProvider.notifier)
        .updateOne(
          id,
          confirmLarge: (entry, byteLength) async {
            asked++;
            expect(byteLength, greaterThan(maxSubscriptionBytes));
            return false;
          },
        );

    expect(asked, 1);
    expect(result?.isSkipped, isTrue);
    expect(result?.isFailure, isFalse);
    expect(container.read(subscriptionUpdateProvider).isBusy, isFalse);
    final rows = await db.query(
      'subscription',
      where: 'id = ?',
      whereArgs: [id],
    );
    expect(rows.single['importState'], 'ready');
    expect(rows.single['ruleCount'], 0);
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

class _LargeContentFetcher implements SubscriptionFetcher {
  @override
  Future<SubscriptionFetchResult> fetch(
    SubscriptionRecord record, {
    bool useValidators = true,
  }) async => SubscriptionFetchResult(
    outcome: SubscriptionFetchOutcome.content,
    content: 'example.com\n',
    byteLength: maxSubscriptionBytes + 1,
    requestedUrl: record.url,
  );
}
