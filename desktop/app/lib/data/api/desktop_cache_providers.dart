library;

import 'dart:async';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_cache_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<void> _refreshReads() async {
    await ref.read(desktopCacheSnapshotProvider.notifier).refresh();
    ref.invalidate(desktopCacheEntriesProvider);
  }
}

final desktopCacheActionProvider =
    NotifierProvider<DesktopCacheActionNotifier, DesktopCacheActionState>(
      DesktopCacheActionNotifier.new,
    );
