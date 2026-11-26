import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/data/db/subscription_repository.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:diting_android/data/db/database_schema.dart';
import 'package:diting_android/data/db/storage_contract.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

SubscriptionRecord record({
  String url = 'https://example.com/rules.txt',
  String name = '示例订阅',
  SubscriptionKind kind = SubscriptionKind.domain,
  bool enabled = true,
  int? groupId,
}) => SubscriptionRecord(
  id: 0,
  url: url,
  name: name,
  sourceType: SubscriptionSourceType.remote,
  kind: kind,
  enabled: enabled,
  ruleCount: 0,
  lastUpdated: 0,
  addedAt: 1,
  importState: SubscriptionImportState.ready,
  lastAttemptAt: 0,
  consecutiveFailureCount: 0,
  mirrorFallback: true,
  groupId: groupId,
);

SubscriptionEntry entry({
  required String url,
  required String name,
  SubscriptionKind kind = SubscriptionKind.domain,
  bool enabled = true,
  String? groupName,
}) => SubscriptionEntry(
  record: record(url: url, name: name, kind: kind, enabled: enabled),
  groupName: groupName,
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late SubscriptionRepository repository;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    for (final statement in DatabaseSchema.statementsFor(
      DatabaseKind.normalRules,
    )) {
      await db.execute(statement);
    }
    repository = SubscriptionRepository(db);
  });

  tearDown(() => db.close());

  test('导入其他模式的订阅时保留分组并跳过重复项', () async {
    await repository.insert(
      record(url: 'https://example.com/rules.txt', name: '已有订阅'),
    );
    final container = ProviderContainer(
      overrides: [
        subscriptionRepositoryProvider.overrideWith((ref) async => repository),
      ],
    );
    addTearDown(container.dispose);

    final result = await container
        .read(subscriptionModeImporterProvider)
        .importEntries([
          entry(
            url: 'https://example.com/rules.txt',
            name: '已有订阅',
            groupName: '常用',
          ),
          entry(
            url: 'https://example.com/hosts.txt',
            name: 'hosts 订阅',
            kind: SubscriptionKind.hosts,
            groupName: '常用',
          ),
        ]);

    expect(result.skipped, 1);
    expect(result.ids, hasLength(1));

    final rows = await repository.all();
    expect(rows, hasLength(2));
    final imported = rows.firstWhere(
      (row) => row.kind == SubscriptionKind.hosts,
    );
    expect(imported.importState, SubscriptionImportState.importing);
    expect(imported.groupId, isNotNull);
    expect((await repository.groups()).single.name, '常用');
  });
}
