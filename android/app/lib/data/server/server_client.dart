library;

import 'dart:async';

import 'package:diting_android/data/server/server_launch_models.dart';
import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/server/server_runtime_models.dart';

const serverChannelName = 'com.haoze.diting/server';
const serverStatusChannelName = 'com.haoze.diting/server_status';

class ServerException implements Exception {
  const ServerException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class ServerClient {
  Future<ServerStatus> status();
  Stream<ServerStatus> watchStatus();
  Future<bool> start({required bool preferRoot});
  Future<bool> stop();
  Future<ServerRootStatus> probeRoot();
  Future<ServerLaunchSettings> getLaunchSettings();
  Future<void> saveLaunchSettings(ServerLaunchSettings settings);
  Future<String?> readConfig();
  Future<void> writeConfig(ServerConfig config);
  Future<ServerConfig> getConfig();
  Future<ServerConfig> saveConfig(ServerConfig config);
  Future<ServerStats> stats();
  Future<ServerQueryResult> queryLog(ServerLogQuery query);
  Future<void> clearQueryLog();
  Future<void> clearCache();
  Future<ServerFilterConfig> refreshFilter([String id = '']);
  Future<ServerFilterCheck> filterCheck(String domain, {String qtype = 'A'});
}
