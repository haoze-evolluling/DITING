library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_models.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  void setQType(String value) {
    if (value == state.qtype) return;
    state = state.copyWith(qtype: value, offset: 0);
  }

  void setStatus(DesktopLogStatus value) {
    if (value == state.status) return;
    state = state.copyWith(status: value, offset: 0);
  }

  void reset() => state = const DesktopLogQuery();

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

class DesktopLogConfigState {
  const DesktopLogConfigState({this.config, this.error, this.saving = false});

  final DesktopQueryLogConfig? config;
  final DesktopApiException? error;
  final bool saving;

  bool get isLoading => config == null && error == null;
}

class DesktopLogConfigNotifier extends Notifier<DesktopLogConfigState> {
  @override
  DesktopLogConfigState build() {
    unawaited(_load());
    return const DesktopLogConfigState();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    try {
      final config = await ref.read(desktopApiClientProvider).queryLogConfig();
      if (ref.mounted) state = DesktopLogConfigState(config: config);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopLogConfigState(config: state.config, error: error);
      }
    }
  }

  Future<DesktopApiException?> save(DesktopQueryLogConfig next) async {
    if (state.saving) return null;
    state = DesktopLogConfigState(config: state.config, saving: true);
    final client = ref.read(desktopApiClientProvider);
    try {
      await client.updateQueryLogConfig(next);
      final config = await client.queryLogConfig();
      if (ref.mounted) state = DesktopLogConfigState(config: config);
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopLogConfigState(config: state.config, error: error);
      }
      return error;
    }
  }
}

final desktopLogConfigProvider =
    NotifierProvider<DesktopLogConfigNotifier, DesktopLogConfigState>(
      DesktopLogConfigNotifier.new,
    );
