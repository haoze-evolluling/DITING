/// Observability state; requests merge `http_request_log` and `dns_log`, DNS queries read
/// `dns_log`.
library;

import 'package:diting_android/data/db/dns_query_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_android/data/db/rust_log_query_core.dart';
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
    final parsed = row.messageFields;
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

  /// One merged item from the native feed aggregate.
  static ObservedRequest fromParsed(Map<String, Object?> row) => ObservedRequest(
    key: row['key'] as String? ?? '',
    timestamp: (row['timestamp'] as num?)?.toInt() ?? 0,
    source: row['source'] == 'https' ? RequestSource.https : RequestSource.dns,
    status: _statusOfToken(row['status'] as String?),
    title: row['title'] as String? ?? '',
    protocol: row['protocol'] as String?,
    packageName: row['packageName'] as String?,
    matchedRule: row['matchedRule'] as String?,
    message: row['message'] as String?,
    cached: row['cached'] as bool? ?? false,
    elapsedMs: (row['elapsedMs'] as num?)?.toInt(),
    blockSubscriptionId: (row['blockSubscriptionId'] as num?)?.toInt(),
  );
}

RequestStatus _statusOfToken(String? token) => switch (token) {
  'passed' => RequestStatus.passed,
  'rewritten' => RequestStatus.rewritten,
  'blocked' => RequestStatus.blocked,
  'bypassed' => RequestStatus.bypassed,
  _ => RequestStatus.error,
};

/// Rows fetched per page. The request page loads one page on entry and appends the next when the
/// list is scrolled to the bottom; reading thousands of rows up front stalled the UI thread.
const int requestFeedPageSize = 50;

/// Request-page query: the legacy four filters. Paging is not part of it — the feed walks a
/// timestamp cursor and owns the page it is on, so changing a filter restarts from the top and a
/// "load more" never re-reads the rows already on screen.
class RequestFeedQuery {
  const RequestFeedQuery({
    this.source = RequestSource.all,
    this.status = RequestStatus.all,
    this.query = '',
  });

  final RequestSource source;
  final RequestStatus status;
  final String query;

  RequestFeedQuery copyWith({
    RequestSource? source,
    RequestStatus? status,
    String? query,
  }) => RequestFeedQuery(
    source: source ?? this.source,
    status: status ?? this.status,
    query: query ?? this.query,
  );
}

class RequestFeedNotifier extends Notifier<RequestFeedQuery> {
  @override
  RequestFeedQuery build() => const RequestFeedQuery();

  void setSource(RequestSource source) {
    if (state.source == source) return;
    // Any filter change belongs to a different result set, so the feed restarts from the top.
    state = state.copyWith(source: source);
  }

  void setStatus(RequestStatus status) {
    if (state.status == status) return;
    state = state.copyWith(status: status);
  }

  void setQuery(String query) {
    if (state.query == query) return;
    state = state.copyWith(query: query);
  }

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
    this.cursor,
    this.loadingMore = false,
  });

  const RequestFeed.empty()
    : items = const [],
      hasMore = false,
      cursor = null,
      loadingMore = false;

  /// The rows of every page fetched so far, newest first.
  final List<ObservedRequest> items;

  /// True while another page may exist.
  final bool hasMore;

  /// `timestamp` of the oldest delivered row; the next page asks for `timestamp <= cursor`.
  final int? cursor;

  /// True while the next page is in flight, so a scroll burst cannot queue it twice.
  final bool loadingMore;

  RequestFeed copyWith({
    List<ObservedRequest>? items,
    bool? hasMore,
    int? cursor,
    bool? loadingMore,
  }) => RequestFeed(
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    cursor: cursor ?? this.cursor,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// One page of the merged feed, read with a `timestamp` cursor.
///
/// The cursor is what keeps this O(1) per page. The old shape asked for `limit: 50 * page`, so
/// reaching page 20 re-read 1 000 rows from each table, re-encoded every one to a Dart map, pushed
/// them through the kernel and parsed them back — and the 10 s log refresh then paid that again.
typedef RequestFeedPage = ({List<ObservedRequest> items, bool hasMore, int? cursor});

/// Express and server modes keep their own database without `http_request_log`, so querying it
/// throws `no such table`.
/// [packageName] narrows both tables to one app; null reads every app.
Future<RequestFeedPage> _loadFeedPage(
  Ref ref,
  RequestFeedQuery query, {
  String? packageName,
  int? before,
  bool watch = false,
}) async {
  // [watch] is only set from `build()`: a page read started by `loadMore()` runs outside the build
  // phase, where `ref.watch` is illegal, but the first page still has to re-run when the work mode
  // or the log database changes.
  final noHttp =
      (watch ? ref.watch(workModeProvider) : ref.read(workModeProvider)) !=
      AppWorkMode.normal;
  // One extra row per table is enough to tell "there is more" without a second count query.
  final window = requestFeedPageSize + 1;

  final dnsFuture = query.source == RequestSource.https
      ? Future.value(const <DnsLogRow>[])
      : () async {
          final db = await (watch
              ? ref.watch(activeLogDatabaseProvider.future)
              : ref.read(activeLogDatabaseProvider.future));
          if (db == null) return const <DnsLogRow>[];
          return DnsQueryRepository(db).recent(
            limit: window,
            status: query.status,
            query: query.query,
            packageName: packageName,
            before: before,
          );
        }();

  final httpFuture = query.source == RequestSource.dns || noHttp
      ? Future.value(const <HttpRequestRecord>[])
      : () async {
          final db = await (watch
              ? ref.watch(mainLogDatabaseProvider.future)
              : ref.read(mainLogDatabaseProvider.future));
          if (db == null) return const <HttpRequestRecord>[];
          return HttpRequestRepository(db).recent(
            limit: window,
            status: query.status,
            query: query.query,
            packageName: packageName,
            before: before,
          );
        }();

  // Await both together: a sequential await returns early when the DNS side throws, leaving the
  // HTTP error unhandled.
  final (dnsRows, httpRows) = await (dnsFuture, httpFuture).wait;

  final merged = RustLogQueryCore.instance.derive('feed', {
    'limit': window,
    'dns': [for (final row in dnsRows) row.toKernelRow()],
    'http': [for (final row in httpRows) row.toKernelRow()],
  });
  final parsed = [
    for (final row in merged['items'] as List? ?? const [])
      ObservedRequest.fromParsed((row as Map).cast<String, Object?>()),
  ];
  final hasMore = parsed.length > requestFeedPageSize;
  final items = hasMore ? parsed.sublist(0, requestFeedPageSize) : parsed;
  return (items: items, hasMore: hasMore, cursor: _cursorOf(items, before));
}

/// The next cursor: the oldest timestamp delivered.
///
/// The bound is inclusive, because rows of one timestamp can straddle a page; the notifier drops
/// the repeats by `key`. It falls back to `before` when a page carried nothing usable, so a caller
/// can never send the same cursor twice and spin.
int? _cursorOf(List<ObservedRequest> items, int? before) {
  if (items.isEmpty) return before;
  var oldest = items.first.timestamp;
  for (final item in items) {
    if (item.timestamp < oldest) oldest = item.timestamp;
  }
  return oldest;
}

/// Signature of one page read; [requestFeedPageLoaderProvider] is the seam widget tests replace so
/// they can exercise paging without a database.
typedef RequestFeedPageLoader =
    Future<RequestFeedPage> Function(
      Ref ref,
      RequestFeedQuery query, {
      String? packageName,
      int? before,
      bool watch,
    });

/// Overridden in tests to a fake that pages an in-memory list.
final requestFeedPageLoaderProvider = Provider<RequestFeedPageLoader>(
  (ref) => _loadFeedPage,
);

/// The merged request feed. Paging is owned here rather than by [RequestFeedQuery], so loading
/// another page appends to what is on screen instead of re-reading it.
class RequestFeedLoader extends AsyncNotifier<RequestFeed> {
  RequestFeedLoader({
    this.packageName,
    required this.watchQuery,
    required this.readQuery,
  });

  /// Null reads every app; set for the per-app page.
  final String? packageName;

  /// The filter source is a different provider for the global and per-app pages, so the loader
  /// takes accessors instead of a provider type (a family instance and an orphan provider have no
  /// common public supertype to store).
  final RequestFeedQuery Function(Ref ref) watchQuery;
  final RequestFeedQuery Function(Ref ref) readQuery;

  /// Cursor of the last page; `null` before the first read.
  int? _cursor;

  /// True once a second page has been requested, which is when live re-reads stop being worth it.
  bool _paged = false;

  bool _loading = false;

  /// Bumped on every restart so a page that lands after a filter change is dropped.
  int _generation = 0;

  @override
  Future<RequestFeed> build() async {
    final query = watchQuery(ref);
    // New rows only matter at the top of the list. Once the user has paged past the first screen
    // the 10 s log revision would make the feed re-read pages that are already above the viewport.
    if (!_paged) ref.watch(dnsLogRevisionProvider);
    final generation = ++_generation;
    _cursor = null;
    _paged = false;
    _loading = false;
    final page = await ref.read(requestFeedPageLoaderProvider)(
      ref,
      query,
      packageName: packageName,
      watch: true,
    );
    if (generation != _generation) return const RequestFeed.empty();
    _cursor = page.cursor;
    return RequestFeed(
      items: page.items,
      hasMore: page.hasMore,
      cursor: page.cursor,
    );
  }

  /// Appends the next page. A no-op while a page is in flight or when the feed is exhausted, so a
  /// scroll burst cannot queue the same cursor twice.
  ///
  /// The cursor bound is inclusive (rows of one timestamp can straddle a page boundary), so repeats
  /// are dropped by [ObservedRequest.key] rather than assumed absent.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || _loading) return;
    _loading = true;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref.read(requestFeedPageLoaderProvider)(
        ref,
        readQuery(ref),
        packageName: packageName,
        before: _cursor,
      );
      if (generation != _generation) return;
      final seen = {for (final item in current.items) item.key};
      final fresh = [
        for (final item in page.items)
          if (seen.add(item.key)) item,
      ];
      _cursor = page.cursor;
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...fresh],
          // A page that only repeated rows means the cursor cannot advance; stop instead of
          // asking for the same bound forever.
          hasMore: page.hasMore && fresh.isNotEmpty,
          cursor: page.cursor,
          loadingMore: false,
        ),
      );
      _paged = true;
    } catch (_) {
      // A failed page must clear the flag, or the footer spinner (and the guard that stops the
      // next request) would stay on forever with the list frozen mid-scroll. The rows already
      // loaded stay; the footer's retry path is a full reload.
      if (generation == _generation) {
        state = AsyncData(current.copyWith(loadingMore: false, hasMore: false));
      }
    } finally {
      _loading = false;
    }
  }
}

final requestFeedProvider =
    AsyncNotifierProvider<RequestFeedLoader, RequestFeed>(
      () => RequestFeedLoader(
        watchQuery: (ref) => ref.watch(requestFeedQueryProvider),
        readQuery: (ref) => ref.read(requestFeedQueryProvider),
      ),
    );

/// Request feed of one app, keyed by package name; same cursor paging as [requestFeedProvider].
final appRequestFeedProvider = AsyncNotifierProvider.autoDispose
    .family<RequestFeedLoader, RequestFeed, String>(
      (packageName) => RequestFeedLoader(
        packageName: packageName,
        watchQuery: (ref) => ref.watch(appRequestFeedQueryProvider(packageName)),
        readQuery: (ref) => ref.read(appRequestFeedQueryProvider(packageName)),
      ),
    );

/// Request count of one app across both tables.
class AppRequestCount {
  const AppRequestCount({required this.packageName, required this.count});

  final String packageName;
  final int count;
}

/// Apps that appear in the request log, most requests first. Rows without a package are left out:
/// they cannot be opened as an app page. Express and server modes have no `http_request_log`, as
/// in the feed.
final requestAppCountsProvider = FutureProvider<List<AppRequestCount>>((
  ref,
) async {
  ref.watch(dnsLogRevisionProvider);
  final noHttp = ref.watch(workModeProvider) != AppWorkMode.normal;

  Future<Map<String, int>> dnsCounts() async {
    final db = await ref.watch(activeLogDatabaseProvider.future);
    return db == null ? const {} : DnsQueryRepository(db).countByPackage();
  }

  Future<Map<String, int>> httpCounts() async {
    if (noHttp) return const {};
    final db = await ref.watch(mainLogDatabaseProvider.future);
    return db == null ? const {} : HttpRequestRepository(db).countByPackage();
  }

  final (dns, http) = await (dnsCounts(), httpCounts()).wait;
  final merged = RustLogQueryCore.instance.derive('appCounts', {
    'dns': [
      for (final entry in dns.entries)
        {'packageName': entry.key, 'count': entry.value},
    ],
    'http': [
      for (final entry in http.entries)
        {'packageName': entry.key, 'count': entry.value},
    ],
  });
  return [
    for (final row in merged['items'] as List? ?? const [])
      AppRequestCount(
        packageName: (row as Map)['packageName'] as String? ?? '',
        count: (row['count'] as num?)?.toInt() ?? 0,
      ),
  ];
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
