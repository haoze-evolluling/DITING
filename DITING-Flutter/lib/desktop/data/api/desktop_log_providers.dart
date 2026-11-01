/// The log branch's data: the service's 24-hour summary, and one page of its query log behind the
/// filters and paging the page owns.
///
/// Separate from `desktop_api_providers.dart` because these reads answer a page, not a snapshot of
/// the core: a log outage must not blank the dashboard, and a dashboard poll must not re-read the
/// log. Both still share the one [desktopApiClientProvider].
library;

import 'dart:async';

import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:diting/desktop/data/api/desktop_api_models.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One `/api/v1/querylog/stats` answer. A failed poll keeps the last figures, exactly like the
/// dashboard's own snapshot: real numbers marked stale beat an empty card.
class DesktopQueryStatsSnapshot {
  const DesktopQueryStatsSnapshot({this.stats, this.error});

  final DesktopQueryStats? stats;
  final DesktopApiException? error;

  bool get isLoading => stats == null && error == null;

  bool get isStale => stats != null && error != null;
}

class DesktopQueryStatsNotifier extends Notifier<DesktopQueryStatsSnapshot> {
  static const pollInterval = Duration(seconds: 10);

  Timer? _timer;

  @override
  DesktopQueryStatsSnapshot build() {
    final client = ref.watch(desktopApiClientProvider);
    _timer?.cancel();
    _timer = null;
    if (ref.watch(desktopPollingEnabledProvider)) {
      _timer = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
      ref.onDispose(() => _timer?.cancel());
    }
    unawaited(_load(client));
    return const DesktopQueryStatsSnapshot();
  }

  Future<void> refresh() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      final stats = await client.queryStats();
      if (ref.mounted) state = DesktopQueryStatsSnapshot(stats: stats);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopQueryStatsSnapshot(stats: state.stats, error: error);
      }
    }
  }
}

final desktopQueryStatsProvider =
    NotifierProvider<DesktopQueryStatsNotifier, DesktopQueryStatsSnapshot>(
      DesktopQueryStatsNotifier.new,
    );

/// What the query table asks the service for. Offset paging because `querylog.SearchQuery` is
/// offset based; the page number is derived, never stored, so it cannot drift from the offset.
class DesktopLogQuery {
  const DesktopLogQuery({
    this.domain = '',
    this.client = '',
    this.qtype = '',
    this.status = DesktopLogStatus.all,
    this.offset = 0,
  });

  static const pageSize = 25;

  final String domain;
  final String client;

  /// A record type from [desktopLogQTypes]; empty means every type.
  final String qtype;

  final DesktopLogStatus status;
  final int offset;

  bool get isFiltered =>
      domain.isNotEmpty ||
      client.isNotEmpty ||
      qtype.isNotEmpty ||
      status != DesktopLogStatus.all;

  DesktopLogQuery copyWith({
    String? domain,
    String? client,
    String? qtype,
    DesktopLogStatus? status,
    int? offset,
  }) => DesktopLogQuery(
    domain: domain ?? this.domain,
    client: client ?? this.client,
    qtype: qtype ?? this.qtype,
    status: status ?? this.status,
    offset: offset ?? this.offset,
  );
}

class DesktopLogQueryNotifier extends Notifier<DesktopLogQuery> {
  @override
  DesktopLogQuery build() => const DesktopLogQuery();

  /// A new search starts again at the first page: keeping the offset would ask for page 4 of a
  /// result set that just became much smaller.
  void setDomain(String value) {
    final domain = value.trim();
    if (domain == state.domain) return;
    state = state.copyWith(domain: domain, offset: 0);
  }

  void setClient(String value) {
    final client = value.trim();
    if (client == state.client) return;
    state = state.copyWith(client: client, offset: 0);
  }

  /// Empty selects every record type, which is what the service does when `qtype` is absent.
  void setQType(String value) {
    if (value == state.qtype) return;
    state = state.copyWith(qtype: value, offset: 0);
  }

  void setStatus(DesktopLogStatus value) {
    if (value == state.status) return;
    state = state.copyWith(status: value, offset: 0);
  }

  void reset() => state = const DesktopLogQuery();

  /// Stops at the last page: the service reports the total, so both ends are known without
  /// reading past them.
  void nextPage(int total) {
    final next = state.offset + DesktopLogQuery.pageSize;
    if (next >= total) return;
    state = state.copyWith(offset: next);
  }

  void previousPage() {
    if (state.offset == 0) return;
    final previous = state.offset - DesktopLogQuery.pageSize;
    state = state.copyWith(offset: previous < 0 ? 0 : previous);
  }
}

final desktopLogQueryProvider =
    NotifierProvider<DesktopLogQueryNotifier, DesktopLogQuery>(
      DesktopLogQueryNotifier.new,
    );

/// The page the current query names. Watching the query makes any filter or page change re-read;
/// a failed read surfaces as an error the table renders with a retry, never as an empty table.
final desktopLogFeedProvider = FutureProvider<QueryLogPage>((ref) async {
  final query = ref.watch(desktopLogQueryProvider);
  return ref
      .watch(desktopApiClientProvider)
      .searchQueries(
        domain: query.domain,
        client: query.client,
        qtype: query.qtype,
        status: query.status,
        limit: DesktopLogQuery.pageSize,
        offset: query.offset,
      );
});

/// `POST /api/v1/querylog/clear`, which also drops the aggregate the summary card shows. A success
/// re-reads both, because the service, not this app, decides what is left.
class DesktopLogClearNotifier extends Notifier<DesktopLogClearState> {
  @override
  DesktopLogClearState build() => const DesktopLogClearState();

  Future<DesktopApiException?> clear() async {
    if (state.pending) return null;
    state = const DesktopLogClearState(pending: true);
    try {
      await ref.read(desktopApiClientProvider).clearQueryLog();
      ref.invalidate(desktopLogFeedProvider);
      await ref.read(desktopQueryStatsProvider.notifier).refresh();
      if (ref.mounted) state = const DesktopLogClearState();
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) state = DesktopLogClearState(error: error);
      return error;
    }
  }
}

class DesktopLogClearState {
  const DesktopLogClearState({this.pending = false, this.error});

  final bool pending;
  final DesktopApiException? error;
}

final desktopLogClearProvider =
    NotifierProvider<DesktopLogClearNotifier, DesktopLogClearState>(
      DesktopLogClearNotifier.new,
    );
