/// Data side of the floating log window: one merged read of `dns_log` and `http_request_log`,
/// plus the cheap count behind the ball's "new blocked" badge.
library;

import 'package:diting_android/data/db/dns_query_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_shared/data/db/legacy_database.dart';
import 'package:diting_android/state/observability_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// Rows the panel keeps; counts on the filter chips are taken over this window.
const floatingLogWindowSize = 200;

/// Result of one read. [available] is false when the database could not be opened at all.
@immutable
class FloatingLogSnapshot {
  const FloatingLogSnapshot({required this.items, this.available = true});

  const FloatingLogSnapshot.unavailable() : items = const [], available = false;

  /// Newest first.
  final List<ObservedRequest> items;
  final bool available;
}

/// Reads the normal-mode database. The handle is shared with the app through sqflite's
/// single-instance map, so it is never closed here: closing it would close the app's too.
class FloatingLogSource {
  Database? _db;
  bool _opening = false;

  Future<Database?> _open() async {
    if (_db case final db? when db.isOpen) return db;
    if (_opening) return null;
    _opening = true;
    try {
      // Never create: the app owns the schema, and a fresh install has nothing to show yet.
      _db = await LegacyDatabase.open(LegacyDatabase.mainFile, create: false);
      return _db;
    } finally {
      _opening = false;
    }
  }

  /// Latest rows of both tables, filtered by [query] in SQL; status filtering is left to the
  /// caller so the chip counts and the list come from the same rows.
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
        // A missing table (fresh install) or a short lock: show what the other table has.
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
      source == RequestSource.dns
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

  /// Blocked requests newer than [since]; both counts ride the timestamp indexes.
  Future<int> blockedSince(int since) async {
    final db = await _open();
    if (db == null) return 0;
    var total = 0;
    for (final sql in const [
      'SELECT COUNT(*) AS n FROM dns_log WHERE timestamp > ? AND '
          "(result = 'BLOCKED' OR message LIKE '%blocked_by=firewall:%')",
      'SELECT COUNT(*) AS n FROM http_request_log WHERE timestamp > ? AND '
          "outcome IN ('blocked', 'invalid')",
    ]) {
      try {
        final rows = await db.rawQuery(sql, [since]);
        total += (rows.firstOrNull?['n'] as num?)?.toInt() ?? 0;
      } on DatabaseException {
        // Same as [load]: one missing table must not hide the other's count.
      }
    }
    return total;
  }
}

/// Counts per status bucket, `all` included, over [items].
Map<RequestStatus, int> floatingLogCounts(List<ObservedRequest> items) {
  final counts = {for (final status in RequestStatus.values) status: 0};
  for (final item in items) {
    counts[item.status] = counts[item.status]! + 1;
  }
  counts[RequestStatus.all] = items.length;
  return counts;
}
