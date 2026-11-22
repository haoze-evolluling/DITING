library;

import 'package:diting_android/data/db/dns_query_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_android/data/db/rust_log_query_core.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

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

  final String key;
  final int timestamp;
  final RequestSource source;
  final RequestStatus status;

  final String title;

  final String? protocol;
  final String? packageName;
  final String? matchedRule;

  final String? message;
  final bool cached;

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

  static ObservedRequest fromParsed(Map<String, Object?> row) =>
      ObservedRequest(
        key: row['key'] as String? ?? '',
        timestamp: (row['timestamp'] as num?)?.toInt() ?? 0,
        source: row['source'] == 'https'
            ? RequestSource.https
            : RequestSource.dns,
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

const int requestFeedPageSize = 50;

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

  final List<ObservedRequest> items;

  final bool hasMore;

  final int? cursor;

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

typedef RequestFeedPage = ({
  List<ObservedRequest> items,
  bool hasMore,
  int? cursor,
});

Future<RequestFeedPage> _loadFeedPage(
  Ref ref,
  RequestFeedQuery query, {
  String? packageName,
  int? before,
  bool watch = false,
}) async {
  Future<Database?> logDb(FutureProvider<Database?> provider) =>
      watch ? ref.watch(provider.future) : ref.read(provider.future);
  final mode = watch ? ref.watch(workModeProvider) : ref.read(workModeProvider);
  final noHttp = !mode.hasTunnelFeatures;
  final window = requestFeedPageSize + 1;

  final dnsFuture = query.source == RequestSource.https
      ? Future.value(const <DnsLogRow>[])
      : () async {
          final db = await logDb(activeLogDatabaseProvider);
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
          final db = await logDb(activeLogDatabaseProvider);
          if (db == null) return const <HttpRequestRecord>[];
          return HttpRequestRepository(db).recent(
            limit: window,
            status: query.status,
            query: query.query,
            packageName: packageName,
            before: before,
          );
        }();

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

int? _cursorOf(List<ObservedRequest> items, int? before) {
  if (items.isEmpty) return before;
  var oldest = items.first.timestamp;
  for (final item in items) {
    if (item.timestamp < oldest) oldest = item.timestamp;
  }
  return oldest;
}

typedef RequestFeedPageLoader = Future<RequestFeedPage> Function(
  Ref ref,
  RequestFeedQuery query, {
  String? packageName,
  int? before,
  bool watch,
});

final requestFeedPageLoaderProvider = Provider<RequestFeedPageLoader>(
  (ref) => _loadFeedPage,
);

class RequestFeedLoader extends AsyncNotifier<RequestFeed> {
  RequestFeedLoader({
    this.packageName,
    required this.watchQuery,
    required this.readQuery,
  });

  final String? packageName;

  final RequestFeedQuery Function(Ref ref) watchQuery;
  final RequestFeedQuery Function(Ref ref) readQuery;

  int? _cursor;

  bool _paged = false;

  bool _loading = false;

  int _generation = 0;

  @override
  Future<RequestFeed> build() async {
    final query = watchQuery(ref);
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
          hasMore: page.hasMore && fresh.isNotEmpty,
          cursor: page.cursor,
          loadingMore: false,
        ),
      );
      _paged = true;
    } catch (_) {
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

final appRequestFeedProvider = AsyncNotifierProvider.autoDispose
    .family<RequestFeedLoader, RequestFeed, String>(
      (packageName) => RequestFeedLoader(
        packageName: packageName,
        watchQuery: (ref) =>
            ref.watch(appRequestFeedQueryProvider(packageName)),
        readQuery: (ref) => ref.read(appRequestFeedQueryProvider(packageName)),
      ),
    );

class AppRequestCount {
  const AppRequestCount({required this.packageName, required this.count});

  final String packageName;
  final int count;
}

final requestAppCountsProvider = FutureProvider<List<AppRequestCount>>((
  ref,
) async {
  ref.watch(dnsLogRevisionProvider);
  final noHttp = !ref.watch(workModeProvider).hasTunnelFeatures;

  Future<Map<String, int>> dnsCounts() async {
    final db = await ref.watch(activeLogDatabaseProvider.future);
    return db == null ? const {} : DnsQueryRepository(db).countByPackage();
  }

  Future<Map<String, int>> httpCounts() async {
    if (noHttp) return const {};
    final db = await ref.watch(activeLogDatabaseProvider.future);
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

const _noDnsRows = <DnsLogRow>[];

final dnsQueryWindowProvider = FutureProvider<List<DnsLogRow>>((ref) async {
  ref.watch(dnsLogRevisionProvider);
  final db = await ref.watch(activeLogDatabaseProvider.future);
  if (db == null) return _noDnsRows;
  return DnsQueryRepository(db).recent(limit: _dnsWindowSize);
});

const _dnsWindowSize = 300;

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
