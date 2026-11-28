import 'package:diting_android/data/db/app_database.dart';
import 'package:diting_android/data/db/database_schema.dart';
import 'package:diting_android/data/db/storage_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('简洁模式日志库与普通模式一样具备 HTTP 记录与按应用流量表', () {
    final express = DatabaseSchema.tableNamesFor(DatabaseKind.expressLogs);
    final normal = DatabaseSchema.tableNamesFor(DatabaseKind.normalLogs);

    expect(normal.contains('http_request_log'), isTrue);
    expect(normal.contains('app_traffic_daily'), isTrue);
    expect(express, contains('http_request_log'));
    expect(express, contains('app_traffic_daily'));
    expect(express, normal, reason: '两种模式的日志库表集合应完全一致');
  });

  test('简洁模式日志库的建表语句覆盖两张新增表及索引', () {
    final statements = DatabaseSchema.statementsFor(DatabaseKind.expressLogs);
    final joined = statements.join('\n');

    expect(joined, contains('CREATE TABLE `http_request_log`'));
    expect(joined, contains('CREATE TABLE `app_traffic_daily`'));
    expect(joined, contains('index_http_request_log_timestamp'));
    expect(joined, contains('index_app_traffic_daily_date'));
  });

  test('普通模式与简洁模式日志库的建表语句数量一致', () {
    expect(
      DatabaseSchema.statementsFor(DatabaseKind.expressLogs).length,
      DatabaseSchema.statementsFor(DatabaseKind.normalLogs).length,
    );
  });

  test('存储 schema 版本已升级到 4（dns_log 补齐客户端与上游字段）', () {
    expect(StorageContract.schemaVersion, 4);
    final rules = DatabaseSchema.statementsFor(DatabaseKind.normalRules)
        .join('\n');
    expect(
      rules,
      contains(
        '(`pattern`, `important`, `appScope`, `appInverted`, `denyallow`, '
        '`dnsType`, `isRegex`)',
      ),
    );
    final logs = DatabaseSchema.statementsFor(DatabaseKind.normalLogs)
        .join('\n');
    for (final column in const [
      '`clientIp`',
      '`clientName`',
      '`protocol`',
      '`upstreamProvider`',
      '`rcode`',
      '`cacheHit`',
      '`durationMs`',
      '`ttl`',
    ]) {
      expect(logs, contains(column), reason: 'dns_log 缺少 $column');
    }
    expect(logs, contains('index_dns_log_clientIp_timestamp'));
    expect(logs, contains('index_dns_log_upstream_provider_timestamp'));
  });

  group('schema v4 迁移', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('v3 日志库升级后补齐 dns_log 新列并保留旧行', () async {
      final dir = await databaseFactory.getDatabasesPath();
      final path = '$dir/${StorageContract.normalLogsDatabase}';
      await databaseFactory.deleteDatabase(path);
      addTearDown(() => databaseFactory.deleteDatabase(path));

      final legacy = await databaseFactory.openDatabase(path);
      await legacy.execute(
        'CREATE TABLE dns_log ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
        'timestamp INTEGER NOT NULL, '
        'queryName TEXT NOT NULL, '
        'queryType INTEGER NOT NULL, '
        'result TEXT NOT NULL, '
        'message TEXT, '
        'cached INTEGER NOT NULL, '
        'blockSubscriptionId INTEGER, '
        'packageName TEXT)',
      );
      await legacy.insert('dns_log', {
        'timestamp': 1,
        'queryName': 'legacy.example',
        'queryType': 1,
        'result': 'blocked',
        'cached': 0,
      });
      await legacy.execute(
        'PRAGMA application_id = ${DatabaseKind.normalLogs.applicationId}',
      );
      await legacy.execute('PRAGMA user_version = 3');
      await legacy.close();

      final upgraded = await AppDatabase.open(
        StorageContract.normalLogsDatabase,
      );
      expect(upgraded, isNotNull);

      final columns = await upgraded!.rawQuery('PRAGMA table_info(dns_log)');
      final names = {for (final row in columns) row['name'] as String};
      expect(
        names,
        containsAll(const [
          'clientIp',
          'clientName',
          'protocol',
          'upstreamProvider',
          'rcode',
          'cacheHit',
          'durationMs',
          'ttl',
        ]),
      );

      final row = (await upgraded.rawQuery(
        'SELECT * FROM dns_log WHERE queryName = ?',
        ['legacy.example'],
      )).single;
      expect(row['clientName'], '');
      expect(row['upstreamProvider'], '');
      expect(row['durationMs'], 0);
      expect(row['ttl'], isNull);

      final indexes = await upgraded.rawQuery('PRAGMA index_list(dns_log)');
      final indexNames = {for (final row in indexes) row['name'] as String};
      expect(indexNames, contains('index_dns_log_clientIp_timestamp'));
      expect(indexNames, contains('index_dns_log_upstream_provider_timestamp'));

      expect(await upgraded.getVersion(), StorageContract.schemaVersion);
      await upgraded.close();
    });
  });
}
