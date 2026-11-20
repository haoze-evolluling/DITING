library;

import 'package:diting_android/data/server/server_client.dart';
import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/server/server_runtime_models.dart';
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
  (ref) => MethodChannelServerClient(),
);

class ServerController extends AsyncNotifier<ServerSnapshot> {
  ServerClient get _client => ref.read(serverClientProvider);

  @override
  Future<ServerSnapshot> build() => _loadAll();

  Future<ServerSnapshot> _loadAll() async {
    final status = await _client.status();
    final config = await _client.getConfig();
    final stats = status.running ? await _client.stats() : const ServerStats();
    return ServerSnapshot(status: status, config: config, stats: stats);
  }

  Future<void> refresh() async {
    state = AsyncData(await _loadAll());
  }

  Future<void> refreshLive() async {
    final current = state.value;
    if (current == null) return;
    final status = await _client.status();
    if (status.running) {
      if (!current.status.running) {
        state = AsyncData(await _loadAll());
        return;
      }
      final stats = await _client.stats();
      state = AsyncData(current.copyWith(status: status, stats: stats));
    } else {
      state = AsyncData(current.copyWith(status: status));
    }
  }

  Future<void> start({required bool preferRoot}) async {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        status: current.status.copyWith(
          starting: true,
          running: false,
          root: preferRoot,
          port: preferRoot ? 53 : 1053,
          clearError: true,
        ),
      ),
    );
    final accepted = await _client.start(preferRoot: preferRoot);
    if (!accepted) {
      final status = await _client.status();
      state = AsyncData(current.copyWith(status: status));
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    state = AsyncData(await _loadAll());
  }

  Future<void> stop() async {
    await _client.stop();
    final status = await _client.status();
    final current = state.value;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          status: status,
          stats: status.running ? current.stats : const ServerStats(),
        ),
      );
    }
  }

  Future<void> saveConfig(ServerConfig config) async {
    final saved = await _client.saveConfig(config);
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(config: saved));
    }
  }

  Future<ServerFilterConfig> refreshFilter([String id = '']) async {
    final filter = await _client.refreshFilter(id);
    final current = state.value;
    if (current != null) {
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
}

final serverControllerProvider =
    AsyncNotifierProvider<ServerController, ServerSnapshot>(
      ServerController.new,
    );

class ServerLogRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final serverLogRevisionProvider =
    NotifierProvider<ServerLogRevision, int>(ServerLogRevision.new);

final serverQueryLogProvider =
    FutureProvider.autoDispose.family<ServerQueryResult, ServerLogQuery>(
      (ref, query) async {
        ref.watch(serverLogRevisionProvider);
        final snapshot = ref.watch(serverControllerProvider).value;
        if (snapshot == null || !snapshot.status.running) {
          return const ServerQueryResult();
        }
        return ref.read(serverClientProvider).queryLog(query);
      },
    );
