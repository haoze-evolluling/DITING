/// The cache page's data: the service's counters and rankings, the config form, and the three
/// persistence actions.
///
/// The service is the only source of truth. Counters and rankings poll on their own timer, the
/// entry list re-reads whenever the search changes, and every write re-reads what the service kept
/// instead of writing the expected result into the form.
library;

import 'dart:async';

import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/data/api/desktop_cache_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One poll of the counters, the rankings and the persistence status.
///
/// A failed poll keeps the last answer: real figures marked stale beat an empty card. The
/// persistence status is attached only when the service answers it, because an older build may not
/// expose `/cache/persist` at all and that must not blank the whole page.
class DesktopCacheSnapshot {
  const DesktopCacheSnapshot({
    this.stats,
    this.topDomains = const [],
    this.persist,
    this.error,
  });

  final DesktopCacheStats? stats;
  final List<DesktopCacheDomain> topDomains;
  final DesktopCachePersist? persist;
  final DesktopApiException? error;

  bool get isLoading => stats == null && error == null;

  bool get isStale => stats != null && error != null;
}

class DesktopCacheSnapshotNotifier extends Notifier<DesktopCacheSnapshot> {
  static const pollInterval = Duration(seconds: 4);

  Timer? _timer;

  @override
  DesktopCacheSnapshot build() {
    final client = ref.watch(desktopApiClientProvider);
    _timer?.cancel();
    _timer = null;
    if (ref.watch(desktopPollingEnabledProvider)) {
      _timer = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
      ref.onDispose(() => _timer?.cancel());
    }
    unawaited(_load(client));
    return const DesktopCacheSnapshot();
  }

  Future<void> refresh() => _load(ref.read(desktopApiClientProvider));

  Future<void> _load(DesktopApiClient client) async {
    try {
      // Sequential on purpose: a failed read must not leave the two other futures' errors
      // unhandled, and the three calls all answer from the same local service.
      final stats = await client.cacheStats();
      final top = await client.cacheTopDomains();
      final persist = await _persistOrNull(client);
      if (ref.mounted) {
        state = DesktopCacheSnapshot(
          stats: stats,
          topDomains: top,
          persist: persist,
        );
      }
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopCacheSnapshot(
          stats: state.stats,
          topDomains: state.topDomains,
          persist: state.persist,
          error: error,
        );
      }
    }
  }

  Future<DesktopCachePersist?> _persistOrNull(DesktopApiClient client) async {
    try {
      return await client.cachePersist();
    } on DesktopApiException {
      return null;
    }
  }
}

final desktopCacheSnapshotProvider =
    NotifierProvider<DesktopCacheSnapshotNotifier, DesktopCacheSnapshot>(
      DesktopCacheSnapshotNotifier.new,
    );

/// The entry search. A change re-reads the list, and a clear returns to the unfiltered page.
class DesktopCacheSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) {
    final query = value.trim();
    if (query == state) return;
    state = query;
  }

  void clear() => state = '';
}

final desktopCacheSearchProvider =
    NotifierProvider<DesktopCacheSearchNotifier, String>(
      DesktopCacheSearchNotifier.new,
    );

/// One page of entries for the current search. The service caps the page; the status chips filter
/// what came back, exactly as the console does, rather than asking for a different query.
final desktopCacheEntriesProvider = FutureProvider<DesktopCacheEntries>((
  ref,
) async {
  final query = ref.watch(desktopCacheSearchProvider);
  return ref.watch(desktopApiClientProvider).cacheEntries(query: query);
});

class DesktopCacheConfigState {
  const DesktopCacheConfigState({this.config, this.error, this.saving = false});

  final DesktopCacheConfig? config;
  final DesktopApiException? error;
  final bool saving;

  bool get isLoading => config == null && error == null;
}

/// `GET` / `POST /api/v1/cache/config`. The engine switch saves on the spot; the policy form saves
/// with its own button; both re-read the config afterwards.
class DesktopCacheConfigNotifier extends Notifier<DesktopCacheConfigState> {
  @override
  DesktopCacheConfigState build() {
    unawaited(_load());
    return const DesktopCacheConfigState();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    try {
      final config = await ref.read(desktopApiClientProvider).cacheConfig();
      if (ref.mounted) state = DesktopCacheConfigState(config: config);
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopCacheConfigState(config: state.config, error: error);
      }
    }
  }

  /// Applies [next] and adopts what the service reports afterwards. A rejection leaves the previous
  /// config in place, so a switch that did not take effect flips back instead of lying.
  Future<DesktopApiException?> save(DesktopCacheConfig next) async {
    if (state.saving) return null;
    state = DesktopCacheConfigState(config: state.config, saving: true);
    final client = ref.read(desktopApiClientProvider);
    try {
      await client.updateCacheConfig(next);
      final config = await client.cacheConfig();
      if (ref.mounted) state = DesktopCacheConfigState(config: config);
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) {
        state = DesktopCacheConfigState(config: state.config, error: error);
      }
      return error;
    }
  }
}

final desktopCacheConfigProvider =
    NotifierProvider<DesktopCacheConfigNotifier, DesktopCacheConfigState>(
      DesktopCacheConfigNotifier.new,
    );

enum DesktopCacheAction { clear, dump, load }

class DesktopCacheActionState {
  const DesktopCacheActionState({this.pending, this.error});

  final DesktopCacheAction? pending;
  final DesktopApiException? error;

  bool get isBusy => pending != null;

  bool isBusyWith(DesktopCacheAction action) => pending == action;
}

/// The three destructive-or-blocking actions. Each one re-reads the counters and the entry list
/// afterwards, because the service, not this app, decides what is left.
class DesktopCacheActionNotifier extends Notifier<DesktopCacheActionState> {
  @override
  DesktopCacheActionState build() => const DesktopCacheActionState();

  Future<DesktopApiException?> clear() async {
    if (state.isBusy) return null;
    state = const DesktopCacheActionState(pending: DesktopCacheAction.clear);
    try {
      await ref.read(desktopApiClientProvider).clearCache();
      await _refreshReads();
      if (ref.mounted) state = const DesktopCacheActionState();
      return null;
    } on DesktopApiException catch (error) {
      if (ref.mounted) state = DesktopCacheActionState(error: error);
      return error;
    }
  }

  /// Returns the failure together with the service's own status, so the caller can report the
  /// entry count the operation actually moved instead of re-reading a field that is not on `GET`.
  Future<(DesktopApiException?, DesktopCachePersist?)> dump() =>
      _runPersist(DesktopCacheAction.dump, (client) => client.dumpCache());

  Future<(DesktopApiException?, DesktopCachePersist?)> load() =>
      _runPersist(DesktopCacheAction.load, (client) => client.loadCache());

  Future<(DesktopApiException?, DesktopCachePersist?)> _runPersist(
    DesktopCacheAction action,
    Future<DesktopCachePersist> Function(DesktopApiClient client) body,
  ) async {
    if (state.isBusy) return (null, null);
    state = DesktopCacheActionState(pending: action);
    final client = ref.read(desktopApiClientProvider);
    try {
      final persist = await body(client);
      await _refreshReads();
      if (ref.mounted) state = const DesktopCacheActionState();
      return (null, persist);
    } on DesktopApiException catch (error) {
      if (ref.mounted) state = DesktopCacheActionState(error: error);
      return (error, null);
    }
  }

  /// Everything the cache page shows is re-read after a write: the counters and rankings poll, and
  /// the entry page is invalidated so the next build asks again.
  Future<void> _refreshReads() async {
    await ref.read(desktopCacheSnapshotProvider.notifier).refresh();
    ref.invalidate(desktopCacheEntriesProvider);
  }
}

final desktopCacheActionProvider =
    NotifierProvider<DesktopCacheActionNotifier, DesktopCacheActionState>(
      DesktopCacheActionNotifier.new,
    );
