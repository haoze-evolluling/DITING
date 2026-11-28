library;

import 'dart:async';

import 'package:diting_android/data/server/server_client.dart';
import 'package:diting_android/data/server/server_launch_models.dart';
import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/data/server/shared_server_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ServerSnapshot {
  const ServerSnapshot({
    this.status = const ServerStatus(),
    this.config = const ServerConfig(),
    this.stats = const ServerStats(),
  });

  final ServerStatus status;
  final ServerConfig config;
  final ServerStats stats;

  ServerSnapshot copyWith({
    ServerStatus? status,
    ServerConfig? config,
    ServerStats? stats,
  }) => ServerSnapshot(
    status: status ?? this.status,
    config: config ?? this.config,
    stats: stats ?? this.stats,
  );
}

final serverClientProvider = Provider<ServerClient>(
  (ref) => SharedServerClient(ref),
);

class ServerController extends AsyncNotifier<ServerSnapshot> {
  static const Duration _startWaitTimeout = Duration(seconds: 25);
  static const Duration _stopWaitTimeout = Duration(seconds: 5);
  static const Duration _fastPollInterval = Duration(milliseconds: 50);
  static const Duration _slowPollInterval = Duration(milliseconds: 200);

  StreamSubscription<ServerStatus>? _statusSub;
  Completer<ServerStatus>? _waiter;
  bool Function(ServerStatus)? _waiterPredicate;
  bool _disposed = false;
  bool _inTransition = false;

  ServerClient get _client => ref.read(serverClientProvider);

  @override
  Future<ServerSnapshot> build() {
    _disposed = false;
    _statusSub?.cancel();
    _statusSub = _client.watchStatus().listen(_onNativeStatus, onError: (_) {});
    ref.onDispose(() {
      _disposed = true;
      _statusSub?.cancel();
      _statusSub = null;
      _clearWaiter();
    });
    return _loadAll();
  }

  Future<ServerSnapshot> _loadAll({ServerStatus? knownStatus}) async {
    final status = knownStatus ?? await _client.status();
    if (status.running) {
      final results = await Future.wait<Object?>([
        _client.getConfig(),
        _client.stats(),
      ]);
      return ServerSnapshot(
        status: status,
        config: results[0]! as ServerConfig,
        stats: results[1]! as ServerStats,
      );
    }
    final config = await _client.getConfig();
    return ServerSnapshot(
      status: status,
      config: config,
      stats: const ServerStats(),
    );
  }

  void _onNativeStatus(ServerStatus next) {
    if (_disposed) return;
    final waiter = _waiter;
    final predicate = _waiterPredicate;
    if (waiter != null &&
        !waiter.isCompleted &&
        predicate != null &&
        predicate(next)) {
      _waiter = null;
      _waiterPredicate = null;
      waiter.complete(next);
    }

    final current = state.value;
    if (current == null || next == current.status) return;
    final becameRunning = !current.status.running && next.running;
    state = AsyncData(
      current.copyWith(
        status: next,
        stats: next.running ? current.stats : const ServerStats(),
      ),
    );
    if (becameRunning && !_inTransition) {
      unawaited(_syncRunningDetails(next));
    }
  }

  Future<void> _syncRunningDetails(ServerStatus status) async {
    try {
      final snapshot = await _loadAll(knownStatus: status);
      if (_disposed) return;
      final latest = state.value;
      if (latest != null && !latest.status.running) return;
      state = AsyncData(snapshot);
    } catch (_) {}
  }

  void _clearWaiter() {
    final waiter = _waiter;
    _waiter = null;
    _waiterPredicate = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(state.value?.status ?? const ServerStatus());
    }
  }

  Future<ServerStatus> _waitForStatus(
    bool Function(ServerStatus) done, {
    required Duration timeout,
  }) async {
    final immediate = await _client.status();
    if (_disposed || done(immediate)) return immediate;

    final completer = Completer<ServerStatus>();
    _waiter = completer;
    _waiterPredicate = done;
    final deadline = DateTime.now().add(timeout);
    var polls = 0;

    Timer? pollTimer;
    void schedulePoll() {
      if (_disposed || completer.isCompleted) return;
      final delay = polls < 20 ? _fastPollInterval : _slowPollInterval;
      polls++;
      pollTimer = Timer(delay, () async {
        if (_disposed || completer.isCompleted) return;
        try {
          final latest = await _client.status();
          if (_disposed || completer.isCompleted) return;
          if (done(latest) || DateTime.now().isAfter(deadline)) {
            if (!completer.isCompleted) completer.complete(latest);
            return;
          }
        } catch (_) {
          if (DateTime.now().isAfter(deadline) && !completer.isCompleted) {
            completer.complete(state.value?.status ?? const ServerStatus());
            return;
          }
        }
        schedulePoll();
      });
    }

    final timeoutTimer = Timer(timeout, () async {
      if (completer.isCompleted) return;
      try {
        final latest = await _client.status();
        if (!completer.isCompleted) completer.complete(latest);
      } catch (_) {
        if (!completer.isCompleted) {
          completer.complete(state.value?.status ?? const ServerStatus());
        }
      }
    });

    schedulePoll();
    try {
      return await completer.future;
    } finally {
      pollTimer?.cancel();
      timeoutTimer.cancel();
      if (identical(_waiter, completer)) {
        _waiter = null;
        _waiterPredicate = null;
      }
    }
  }

  Future<void> refresh() async {
    final snapshot = await _loadAll();
    if (!_disposed) {
      state = AsyncData(snapshot);
    }
  }

  Future<void> refreshLive() async {
    final current = state.value;
    if (current == null || _inTransition) return;
    final status = await _client.status();
    if (_disposed) return;
    if (status.running) {
      if (!current.status.running) {
        final snapshot = await _loadAll(knownStatus: status);
        if (!_disposed) state = AsyncData(snapshot);
        return;
      }
      final stats = await _client.stats();
      if (!_disposed) {
        state = AsyncData(current.copyWith(status: status, stats: stats));
      }
    } else if (status != current.status || current.status.running) {
      state = AsyncData(
        current.copyWith(status: status, stats: const ServerStats()),
      );
    }
  }

  Future<void> start({required bool preferRoot}) async {
    final current = state.value;
    if (current == null) return;
    _inTransition = true;
    state = AsyncData(
      current.copyWith(
        status: current.status.copyWith(
          starting: true,
          stopping: false,
          restarting: false,
          running: false,
          root: preferRoot,
          port: preferRoot ? 53 : 1053,
          clearError: true,
        ),
      ),
    );
    try {
      final accepted = await _client.start(preferRoot: preferRoot);
      if (_disposed) return;
      if (!accepted) {
        final status = await _client.status();
        if (!_disposed) {
          state = AsyncData(
            current.copyWith(status: status, stats: const ServerStats()),
          );
        }
        return;
      }
      final settled = await _waitForStatus(
        (status) => status.running || (!status.starting && !status.stopping),
        timeout: _startWaitTimeout,
      );
      if (_disposed) return;
      final base = state.value ?? current;
      state = AsyncData(
        base.copyWith(
          status: settled,
          stats: settled.running ? base.stats : const ServerStats(),
        ),
      );
      if (settled.running) {
        final snapshot = await _loadAll(knownStatus: settled);
        if (!_disposed && (state.value?.status.running ?? false)) {
          state = AsyncData(snapshot);
        }
      }
    } finally {
      _inTransition = false;
    }
  }

  Future<void> stop() async {
    final current = state.value;
    _inTransition = true;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          status: current.status.copyWith(
            running: false,
            starting: false,
            stopping: true,
            restarting: false,
          ),
        ),
      );
    }
    try {
      await _client.stop();
      if (_disposed) return;
      final settled = await _waitForStatus(
        (status) => !status.running && !status.starting && !status.stopping,
        timeout: _stopWaitTimeout,
      );
      if (_disposed) return;
      final latest = state.value ?? current;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(
            status: settled,
            stats: settled.running ? latest.stats : const ServerStats(),
          ),
        );
      }
    } finally {
      _inTransition = false;
    }
  }

  Future<void> saveConfig(ServerConfig config) async {
    final saved = await _client.saveConfig(config);
    final current = state.value;
    if (!_disposed && current != null) {
      state = AsyncData(current.copyWith(config: saved));
    }
  }

  Future<ServerFilterConfig> refreshFilter([String id = '']) async {
    final filter = await _client.refreshFilter(id);
    final current = state.value;
    if (!_disposed && current != null) {
      state = AsyncData(
        current.copyWith(config: current.config.copyWith(filter: filter)),
      );
    }
    return filter;
  }

  Future<void> clearQueryLog() async {
    await _client.clearQueryLog();
    ref.read(serverLogRevisionProvider.notifier).bump();
    await refreshLive();
  }

  Future<void> clearCache() async {
    await _client.clearCache();
    await refreshLive();
  }

  /// 自动更新或外部修改后可单独重读配置，避免整页重建快照。
  Future<void> refreshConfig() async {
    final config = await _client.getConfig();
    final current = state.value;
    if (!_disposed && current != null) {
      state = AsyncData(current.copyWith(config: config));
    }
  }
}

final serverControllerProvider =
    AsyncNotifierProvider<ServerController, ServerSnapshot>(
      ServerController.new,
    );

/// 开机自启与异常重启属于进程级偏好，不进入服务器配置数据库。
class ServerLaunchController extends AsyncNotifier<ServerLaunchSettings> {
  @override
  Future<ServerLaunchSettings> build() =>
      ref.read(serverClientProvider).getLaunchSettings();

  Future<void> save(ServerLaunchSettings next) async {
    final previous = state.value;
    state = AsyncData(next);
    try {
      await ref.read(serverClientProvider).saveLaunchSettings(next);
    } catch (error, stackTrace) {
      state = previous == null
          ? AsyncError(error, stackTrace)
          : AsyncData(previous);
      rethrow;
    }
  }
}

final serverLaunchSettingsProvider =
    AsyncNotifierProvider<ServerLaunchController, ServerLaunchSettings>(
      ServerLaunchController.new,
    );

class ServerLogRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final serverLogRevisionProvider = NotifierProvider<ServerLogRevision, int>(
  ServerLogRevision.new,
);

final serverQueryLogProvider = FutureProvider.autoDispose
    .family<ServerQueryResult, ServerLogQuery>((ref, query) async {
      ref.watch(serverLogRevisionProvider);
      final snapshot = ref.watch(serverControllerProvider).value;
      if (snapshot == null) {
        return const ServerQueryResult();
      }
      // 历史日志保存在数据库里，服务未监听的时也能查询。
      return ref.read(serverClientProvider).queryLog(query);
    });
