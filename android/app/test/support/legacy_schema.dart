import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The exact 1.4.3 table layout, read off the device with `sqlite3 .schema`. `authority`,
/// `matchedRule` and `blockSubscriptionId` are nullable; `dns_log.cached` is INTEGER read `== 1`
Future<void> createLegacySchema(Database db) async {
  await db.execute(
    'CREATE TABLE http_request_log ('
    'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
    'timestamp INTEGER NOT NULL, '
    'packageName TEXT NOT NULL, '
    'authority TEXT, '
    'protocol TEXT NOT NULL, '
    'outcome TEXT NOT NULL, '
    'matchedRule TEXT, '
    'blockSubscriptionId INTEGER)',
  );
  await db.execute(
    'CREATE INDEX index_http_request_log_timestamp '
    'ON http_request_log (timestamp)',
  );
  await db.execute(
    'CREATE INDEX index_http_request_log_outcome_timestamp '
    'ON http_request_log (outcome, timestamp)',
  );
  await db.execute(
    'CREATE TABLE dns_log ('
    'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
    'timestamp INTEGER NOT NULL, '
    'queryName TEXT NOT NULL, '
    'queryType INTEGER NOT NULL, '
    'result TEXT NOT NULL, '
    'message TEXT, '
    'cached INTEGER NOT NULL DEFAULT 0, '
    'blockSubscriptionId INTEGER, '
    'packageName TEXT)',
  );
  await db.execute(
    'CREATE INDEX index_dns_log_result_cached_timestamp '
    'ON dns_log (result, cached, timestamp)',
  );
  await db.execute(
    'CREATE TABLE app_traffic_daily ('
    'date TEXT NOT NULL, '
    'package_name TEXT NOT NULL, '
    'app_name TEXT NOT NULL, '
    'tx_bytes INTEGER NOT NULL, '
    'rx_bytes INTEGER NOT NULL, '
    'updated_at INTEGER NOT NULL, '
    'PRIMARY KEY(date, package_name))',
  );
}

/// Inserts one `http_request_log` row; `authority` is null when TLS failed before the request line.
Future<int> insertHttpRow(
  Database db, {
  required int timestamp,
  required String outcome,
  String packageName = 'com.example.app',
  String? authority,
  String protocol = 'h2',
  String? matchedRule,
  int? blockSubscriptionId,
}) => db.insert('http_request_log', {
  'timestamp': timestamp,
  'packageName': packageName,
  'authority': authority,
  'protocol': protocol,
  'outcome': outcome,
  'matchedRule': matchedRule,
  'blockSubscriptionId': blockSubscriptionId,
});

/// Inserts one `dns_log` row; `queryType` defaults to 1 (A) because 0 marks connection log lines.
Future<int> insertDnsRow(
  Database db, {
  required int timestamp,
  required String queryName,
  required String result,
  int queryType = 1,
  String? message,
  bool cached = false,
  String? packageName,
}) => db.insert('dns_log', {
  'timestamp': timestamp,
  'queryName': queryName,
  'queryType': queryType,
  'result': result,
  'message': message,
  'cached': cached ? 1 : 0,
  'packageName': packageName,
});

/// Inserts one `app_traffic_daily` row.
Future<int> insertTrafficRow(
  Database db,
  String date,
  String packageName, {
  required int tx,
  required int rx,
  String appName = '',
  int updatedAt = 1,
}) => db.insert('app_traffic_daily', {
  'date': date,
  'package_name': packageName,
  'app_name': appName,
  'tx_bytes': tx,
  'rx_bytes': rx,
  'updated_at': updatedAt,
});
