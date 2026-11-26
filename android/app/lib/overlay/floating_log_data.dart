library;

import 'package:diting_android/data/db/dns_query_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_android/data/db/app_database.dart';
import 'package:diting_android/state/observability_providers.dart';
import 'package:diting_android/data/errors.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

const floatingLogWindowSize = 200;

@immutable
class FloatingLogSnapshot {
  const FloatingLogSnapshot({required this.items, this.available = true});

  const FloatingLogSnapshot.unavailable() : items = const [], available = false;

  final List<ObservedRequest> items;
  final bool available;
}

class FloatingLogSource {
  FloatingLogSource({required this.databaseName, this.httpEnabled = true});

  final String databaseName;

  final bool httpEnabled;

  Database? _db;
  bool _opening = false;

  Future<Database?> _open() async {
    if (_db case final db? when db.isOpen) return db;
    if (_opening) return null;
    _opening = true;
    try {
      _db = await AppDatabase.open(databaseName, create: false);
      return _db;
    } finally {
      _opening = false;
    }
  }

  Future<FloatingLogSnapshot> load({
    String query = '',
    RequestSource source = RequestSource.all,
  }) async {
    final db = await _open();
    if (db == null) return const FloatingLogSnapshot.unavailable();
    Future<List<T>> guard<T>(Future<List<T>> Function() read) async {
      try {
        return await read();
      } on DatabaseException catch (error) {
        debugPrint('floating log read failed: $error');
        return <T>[];
      }
    }

    final (dns, http) = await (
      source == RequestSource.https
          ? Future.value(const <DnsLogRow>[])
          : guard(
              () =>
                  DnsQueryRepository(db)
                      .recent(limit: floatingLogWindowSize, query: query),
            ),
      source == RequestSource.dns || !httpEnabled
          ? Future.value(const <HttpRequestRecord>[])
          : guard(
              () =>
                  HttpRequestRepository(db)
                      .recent(limit: floatingLogWindowSize, query: query),
            ),
    ).wait;
    final items = <ObservedRequest>[
      for (final row in dns) ObservedRequest.fromDns(row),
      for (final row in http) ObservedRequest.fromHttp(row),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return FloatingLogSnapshot(
      items: items.take(floatingLogWindowSize).toList(growable: false),
    );
  }

  Future<int> blockedSince(int since) async {
    final db = await _open();
    if (db == null) return 0;
    var total = 0;
    final queries = [
      'SELECT COUNT(*) AS n FROM dns_log WHERE timestamp > ? AND '
          "(result = 'BLOCKED' OR message LIKE '%blocked_by=firewall:%')",
      if (httpEnabled)
        'SELECT COUNT(*) AS n FROM http_request_log WHERE timestamp > ? AND '
            "outcome IN ('blocked', 'invalid')",
    ];
    for (final sql in queries) {
      try {
        final rows = await db.rawQuery(sql, [since]);
        total += (rows.firstOrNull?['n'] as num?)?.toInt() ?? 0;
      } on DatabaseException {
        ignoreError();
      }
    }
    return total;
  }
}

Map<RequestStatus, int> floatingLogCounts(List<ObservedRequest> items) {
  final counts = {for (final status in RequestStatus.values) status: 0};
  for (final item in items) {
    counts[item.status] = counts[item.status]! + 1;
  }
  counts[RequestStatus.all] = items.length;
  return counts;
}
