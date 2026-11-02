/// Observability state; requests merge `http_request_log` and `dns_log`, DNS queries read
/// `dns_log`.
library;

import 'package:diting_android/data/db/dns_query_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_shared/data/db/legacy_database.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

/// One record merged from the DNS and HTTPS tables; only the non-null per-table fields render.
class ObservedRequest {
  const ObservedRequest({
    required this.key,
    required this.timestamp,
    required this.source,
    required this.status,
    required this.title,
    this.protocol,
    this.packageName,
    this.matchedRule,
    this.message,
    this.cached = false,
    this.elapsedMs,
    this.blockSubscriptionId,
  });

  /// `https-<id>` or `dns-<id>`, shaped like the legacy `RequestLogItem.key`.
  final String key;
  final int timestamp;
  final RequestSource source;
  final RequestStatus status;

  /// Authority for HTTPS rows (possibly empty), query name for DNS rows.
  final String title;

  /// HTTPS only (`h2` / `http/1.1`).
  final String? protocol;
  final String? packageName;
  final String? matchedRule;

  /// Raw DNS message (`app=.., resolved=.., elapsed=..`).
  final String? message;
  final bool cached;

  /// `elapsed=NNms` for DNS rows; null and hidden for HTTPS, which has no column.
  final int? elapsedMs;
  final int? blockSubscriptionId;

  static ObservedRequest fromHttp(HttpRequestRecord record) => ObservedRequest(
    key: 'https-${record.id}',
    timestamp: record.timestamp,
    source: RequestSource.https,
    status: record.status,
    title: record.authority ?? '',
    protocol: record.protocol,
    packageName: record.packageName,
    matchedRule: record.matchedRule,
    blockSubscriptionId: record.blockSubscriptionId,
  );

  static ObservedRequest fromDns(DnsLogRow row) {
    final parsed = DnsLogMessage.parse(row.message);
    return ObservedRequest(
      key: 'dns-${row.id}',
      timestamp: row.timestamp,
      source: RequestSource.dns,
      status: row.status,
      title: row.queryName,
      packageName: row.packageName,
      matchedRule: parsed.blockedBy,
      message: row.message,
      cached: row.cached,
      elapsedMs: parsed.elapsedMs,
      blockSubscriptionId: row.blockSubscriptionId,
    );
  }
}

/// Rows fetched per page. The request page loads one page on entry and appends the next when the
/// list is scrolled to the bottom; reading thousands of rows up front stalled the UI thread.
const int requestFeedPageSize = 50;

/// Request-page query: the legacy four filters (source, status, keyword) plus the page count.
class RequestFeedQuery {
  const RequestFeedQuery({
    this.source = RequestSource.all,
    this.status = RequestStatus.all,
    this.query = '',
    this.page = 1,
  });

  final RequestSource source;
  final RequestStatus status;
  final String query;

  /// Pages already revealed; 1 means only the first [requestFeedPageSize] rows.
  final int page;

  /// Rows to read: pages accumulate, the repository has no OFFSET.
  int get limit => requestFeedPageSize * page;

  RequestFeedQuery copyWith({
    RequestSource? source,
    RequestStatus? status,
    String? query,
    int? page,
  }) => RequestFeedQuery(
    source: source ?? this.source,
    status: status ?? this.status,
    query: query ?? this.query,
    page: page ?? this.page,
  );
}

class RequestFeedNotifier extends Notifier<RequestFeedQuery> {
  @override
  RequestFeedQuery build() => const RequestFeedQuery();

  void setSource(RequestSource source) {
    if (state.source == source) return;
    // Any filter change restarts paging: the old page count belongs to the old result set.
    state = state.copyWith(source: source, page: 1);
  }

  void setStatus(RequestStatus status) {
    if (state.status == status) return;
    state = state.copyWith(status: status, page: 1);
  }

  void setQuery(String query) {
    if (state.query == query) return;
    state = state.copyWith(query: query, page: 1);
  }

  /// Reveals the next page; the feed provider then re-reads with the larger window.
  void loadMore() => state = state.copyWith(page: state.page + 1);

  void reset() => state = const RequestFeedQuery();
}

final requestFeedQueryProvider =
    NotifierProvider<RequestFeedNotifier, RequestFeedQuery>(
      RequestFeedNotifier.new,
    );

/// Filters of the per-app request page, keyed by package name. Kept apart from
/// [requestFeedQueryProvider] so filtering one app leaves the full list untouched, and disposed on
/// leave so reopening an app starts unfiltered.
final appRequestFeedQueryProvider = NotifierProvider.autoDispose
    .family<RequestFeedNotifier, RequestFeedQuery, String>(
      (_) => RequestFeedNotifier(),
    );

class RequestFeed {
  const RequestFeed({
    required this.items,
    required this.hasMore,
    this.page = 1,
  });

  const RequestFeed.empty() : items = const [], hasMore = false, page = 1;

  /// The rows of every page requested so far, newest first.
  final List<ObservedRequest> items;

  /// True when at least one source filled the requested window, so another page may exist.
  final bool hasMore;

  /// The page this feed was read for. While [RequestFeedQuery.page] is ahead of it the next page
  /// is still loading, which is how the page derives its loading state without a second flag.
  final int page;
}

/// Express keeps its own database without `http_request_log`, so querying it throws `no such
/// table`.
/// [packageName] narrows both tables to one app; null reads every app.
Future<RequestFeed> _loadRequestFeed(
  Ref ref,
  RequestFeedQuery query, {
  String? packageName,
}) async {
  final express = ref.watch(workModeProvider) == AppWorkMode.express;

  final dnsFuture = query.source == RequestSource.https
      ? Future.value(const <DnsLogRow>[])
      : () async {
          final db = await ref.watch(activeLogDatabaseProvider.future);
          if (db == null) return const <DnsLogRow>[];
          return DnsQueryRepository(db).recent(
            limit: query.limit,
            status: query.status,
            query: query.query,
            packageName: packageName,
          );
        }();

  final httpFuture = query.source == RequestSource.dns || express
      ? Future.value(const <HttpRequestRecord>[])
      : () async {
          final db = await ref.watch(mainLogDatabaseProvider.future);
          if (db == null) return const <HttpRequestRecord>[];
          return HttpRequestRepository(db).recent(
            limit: query.limit,
            status: query.status,
            query: query.query,
            packageName: packageName,
          );
        }();

  // Await both together: a sequential await returns early when the DNS side throws, leaving the
  // HTTP error unhandled.
  final (dnsRows, httpRows) = await (dnsFuture, httpFuture).wait;

  final items = <ObservedRequest>[
    for (final row in dnsRows) ObservedRequest.fromDns(row),
    for (final row in httpRows) ObservedRequest.fromHttp(row),
  ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  return RequestFeed(
    items: items.take(query.limit).toList(growable: false),
    hasMore: dnsRows.length >= query.limit || httpRows.length >= query.limit,
    page: query.page,
  );
}

final requestFeedProvider = FutureProvider<RequestFeed>((ref) async {
  ref.watch(dnsLogRevisionProvider);
  return _loadRequestFeed(ref, ref.watch(requestFeedQueryProvider));
});

/// Request feed of one app, keyed by package name.
final appRequestFeedProvider = FutureProvider.autoDispose
    .family<RequestFeed, String>((ref, packageName) async {
      ref.watch(dnsLogRevisionProvider);
      return _loadRequestFeed(
        ref,
        ref.watch(appRequestFeedQueryProvider(packageName)),
        packageName: packageName,
      );
    });

/// Request count of one app across both tables.
class AppRequestCount {
  const AppRequestCount({required this.packageName, required this.count});

  final String packageName;
  final int count;
}

/// Apps that appear in the request log, most requests first. Rows without a package are left out:
/// they cannot be opened as an app page. Express has no `http_request_log`, as in the feed.
final requestAppCountsProvider = FutureProvider<List<AppRequestCount>>((
  ref,
) async {
  ref.watch(dnsLogRevisionProvider);
  final express = ref.watch(workModeProvider) == AppWorkMode.express;

  Future<Map<String, int>> dnsCounts() async {
    final db = await ref.watch(activeLogDatabaseProvider.future);
    return db == null ? const {} : DnsQueryRepository(db).countByPackage();
  }

  Future<Map<String, int>> httpCounts() async {
    if (express) return const {};
    final db = await ref.watch(mainLogDatabaseProvider.future);
    return db == null ? const {} : HttpRequestRepository(db).countByPackage();
  }

  final (dns, http) = await (dnsCounts(), httpCounts()).wait;
  final merged = <String, int>{...dns};
  http.forEach((name, count) => merged[name] = (merged[name] ?? 0) + count);
  return [
    for (final entry in merged.entries)
      AppRequestCount(packageName: entry.key, count: entry.value),
  ]..sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.packageName.compareTo(b.packageName);
  });
});

/// The main `diting_database`, the only one with `http_request_log` and `app_traffic_daily`.
final mainLogDatabaseProvider = FutureProvider<Database?>(
  (ref) => LegacyDatabase.open(LegacyDatabase.mainFile),
);

/// Empty result reused for normal empty states.
const _noDnsRows = <DnsLogRow>[];

/// Overview window for the DNS page, independent of the status chips.
final dnsQueryWindowProvider = FutureProvider<List<DnsLogRow>>((ref) async {
  ref.watch(dnsLogRevisionProvider);
  final db = await ref.watch(activeLogDatabaseProvider.future);
  if (db == null) return _noDnsRows;
  return DnsQueryRepository(db).recent(limit: _dnsWindowSize);
});

/// Covers a debugging session without slowing the first frame.
const _dnsWindowSize = 300;

/// Selected status filter. The keyword goes to SQL; the toggles filter fetched rows.
class DnsQueryStatusNotifier extends Notifier<RequestStatus> {
  @override
  RequestStatus build() => RequestStatus.all;

  void select(RequestStatus status) {
    if (state == status) return;
    state = status;
  }
}

final dnsQueryStatusProvider =
    NotifierProvider<DnsQueryStatusNotifier, RequestStatus>(
      DnsQueryStatusNotifier.new,
    );

/// The keyword goes into SQL (`LIKE`), since Dart-side filtering misses rows outside the window.
class DnsQueryTextNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    if (state == query) return;
    state = query;
  }

  void clear() => state = '';
}

final dnsQueryTextProvider = NotifierProvider<DnsQueryTextNotifier, String>(
  DnsQueryTextNotifier.new,
);

final dnsQueriesProvider = FutureProvider<List<DnsLogRow>>((ref) async {
  ref.watch(dnsLogRevisionProvider);
  final status = ref.watch(dnsQueryStatusProvider);
  final query = ref.watch(dnsQueryTextProvider);
  final db = await ref.watch(activeLogDatabaseProvider.future);
  if (db == null) return _noDnsRows;
  return DnsQueryRepository(db)
      .recent(limit: _dnsWindowSize, status: status, query: query);
});
