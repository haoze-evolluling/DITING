import 'dart:async';

import 'package:diting_android/data/server/server_client.dart';
import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/server/server_runtime_models.dart';

class FakeServerClient implements ServerClient {
  FakeServerClient({
    ServerStatus? status,
    ServerConfig? config,
    ServerStats? stats,
  }) : _status = status ?? const ServerStatus(),
       _config = config ?? ServerConfig.defaults(),
       _stats = stats ?? const ServerStats();

  final _statusController = StreamController<ServerStatus>.broadcast();
  ServerStatus _status;
  ServerConfig _config;
  final ServerStats _stats;

  void emitStatus(ServerStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  void dispose() {
    _statusController.close();
  }

  @override
  Future<ServerStatus> status() async => _status;

  @override
  Stream<ServerStatus> watchStatus() => _statusController.stream;

  @override
  Future<bool> start({required bool preferRoot}) async {
    emitStatus(
      ServerStatus(
        running: true,
        root: preferRoot,
        port: preferRoot ? 53 : 1053,
        addresses: [preferRoot ? '0.0.0.0:53' : '0.0.0.0:1053'],
      ),
    );
    return true;
  }

  @override
  Future<bool> stop() async {
    emitStatus(const ServerStatus());
    return true;
  }

  @override
  Future<ServerRootStatus> probeRoot() async =>
      const ServerRootStatus(available: false, message: 'test');

  @override
  Future<String?> readConfig() async => null;

  @override
  Future<void> writeConfig(ServerConfig config) async => _config = config;

  @override
  Future<ServerConfig> getConfig() async => _config;

  @override
  Future<ServerConfig> saveConfig(ServerConfig config) async {
    _config = config;
    return config;
  }

  @override
  Future<ServerStats> stats() async => _stats;

  @override
  Future<ServerQueryResult> queryLog(ServerLogQuery query) async =>
      const ServerQueryResult();

  @override
  Future<void> clearQueryLog() async {}

  @override
  Future<ServerFilterConfig> refreshFilter([String id = '']) async =>
      _config.filter;

  @override
  Future<ServerFilterCheck> filterCheck(
    String domain, {
    String qtype = 'A',
  }) async => const ServerFilterCheck(blocked: false, action: 'pass');
}
