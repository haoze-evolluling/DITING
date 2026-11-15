import 'package:diting_android/data/db/http_request_repository.dart'
    show RequestStatus;
import 'package:diting_android/data/export/request_log_csv_exporter.dart';
import 'package:diting_android/data/export/request_log_export_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE dns_log (id INTEGER PRIMARY KEY, timestamp INTEGER, '
      'queryName TEXT, queryType INTEGER, result TEXT, cached INTEGER, '
      'message TEXT, packageName TEXT, blockSubscriptionId INTEGER)',
    );
    await db.execute(
      'CREATE TABLE http_request_log (id INTEGER PRIMARY KEY, '
      'timestamp INTEGER, packageName TEXT, authority TEXT, protocol TEXT, '
      'outcome TEXT, matchedRule TEXT, blockSubscriptionId INTEGER)',
    );
    // 1000: passed DNS; its host and message carry quote/comma characters on purpose.
    await db.insert('dns_log', {
      'id': 1,
      'timestamp': 1000,
      'queryName': 'q,"x"',
      'queryType': 1,
      'result': 'PASSED',
      'cached': 0,
      'message': null,
      'packageName': 'com.a',
    });
    await db.insert('dns_log', {
      'id': 2,
      'timestamp': 2000,
      'queryName': 'b1.example',
      'queryType': 1,
      'result': 'BLOCKED',
      'cached': 0,
      'message': null,
      'packageName': 'com.b',
    });
    await db.insert('dns_log', {
      'id': 3,
      'timestamp': 3000,
      'queryName': 'a2.example',
      'queryType': 1,
      'result': 'PASSED',
      'cached': 1,
      'message': 'app=x, note="hi"',
      'packageName': 'com.a',
    });
    await db.insert('http_request_log', {
      'id': 4,
      'timestamp': 1500,
      'packageName': 'com.a',
      'authority': 'h1.example',
      'protocol': 'h2',
      'outcome': 'allowed',
    });
    await db.insert('http_request_log', {
      'id': 5,
      'timestamp': 2500,
      'packageName': 'com.b',
      'authority': 'h2.example',
      'protocol': 'h2',
      'outcome': 'blocked',
    });
  });

  tearDown(() => db.close());

  Future<(String, RequestLogExportResult)> run(
    RequestLogExportOptions options,
  ) async {
    final buffer = StringBuffer();
    final result = await const RequestLogCsvExporter().exportTo(
      (chunk) async => buffer.write(chunk),
      options: options,
      source: RequestLogExportSource(dnsDb: db, httpDb: db),
      appLabels: const {'com.a': 'App A', 'com.b': 'App B'},
    );
    return (buffer.toString(), result);
  }

  test('默认导出全部记录，表头完整并按时间倒序', () async {
    final (csv, result) = await run(const RequestLogExportOptions());

    expect(result.count, 5);
    expect(result.truncated, isFalse);
    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(
      csv,
      contains(
        '"时间","来源","状态","应用名称","应用包名","主机/查询","协议",'
        '"匹配规则","耗时(ms)","缓存","拦截订阅","原始消息"',
      ),
    );
    final lines = csv
        .replaceFirst('\uFEFF', '')
        .split('\r\n')
        .where((line) => line.isNotEmpty)
        .toList();
    expect(lines.length, 6); // header + five rows
    expect(lines[1], contains('"a2.example"'));
    expect(lines[1], contains('"App A"'));
    expect(lines[2], contains('"h2.example"'));
  });

  test('CSV 字段按 RFC 4180 转义引号与逗号', () async {
    final (csv, _) = await run(const RequestLogExportOptions());

    // The DNS host q,"x" becomes "q,""x"""; the message keeps its comma and doubled quotes.
    expect(csv, contains('"q,""x"""'));
    expect(csv, contains('"app=x, note=""hi"""'));
  });

  test('按应用、状态、时间段与条数过滤', () async {
    final byApp = await run(const RequestLogExportOptions(packages: {'com.a'}));
    expect(byApp.$2.count, 3);

    final blocked = await run(
      const RequestLogExportOptions(status: RequestStatus.blocked),
    );
    expect(blocked.$2.count, 2);

    final window = await run(
      RequestLogExportOptions(
        range: RequestLogExportRange.custom,
        customStart: DateTime.fromMillisecondsSinceEpoch(2000),
        customEnd: DateTime.fromMillisecondsSinceEpoch(2500),
      ),
    );
    expect(window.$2.count, 2);

    final capped = await run(const RequestLogExportOptions(maxRows: 2));
    expect(capped.$2.count, 2);
    expect(capped.$2.truncated, isTrue);
  });

  test('只导出选中的字段', () async {
    final (csv, _) = await run(
      const RequestLogExportOptions(
        columns: {RequestLogColumn.time, RequestLogColumn.host},
      ),
    );
    expect(csv, contains('"时间","主机/查询"'));
    expect(csv, isNot(contains('"应用名称"')));
  });
}
