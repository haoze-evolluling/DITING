import 'package:diting_shared/data/db/database_schema.dart';
import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('存储 schema 版本已升级到 2（简洁日志库补表）', () {
    expect(StorageContract.schemaVersion, 2);
  });
}
