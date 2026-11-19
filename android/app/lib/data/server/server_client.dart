/// Typed client for `com.haoze.diting/server`.
library;

import 'dart:convert';

import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:flutter/services.dart';

const serverChannelName = 'com.haoze.diting/server';

class ServerException implements Exception {
  const ServerException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class ServerClient {
  Future<ServerStatus> status();
  Future<bool> start({required bool preferRoot});
  Future<bool> stop();
  Future<ServerRootStatus> probeRoot();
  Future<String?> readConfig();
  Future<void> writeConfig(ServerConfig config);
  Future<ServerConfig> getConfig();
  Future<ServerConfig> saveConfig(ServerConfig config);
  Future<ServerStats> stats();
  Future<ServerQueryResult> queryLog(ServerLogQuery query);
  Future<void> clearQueryLog();
  Future<ServerFilterConfig> refreshFilter([String id = '']);
  Future<ServerFilterCheck> filterCheck(String domain, {String qtype = 'A'});
}

class MethodChannelServerClient implements ServerClient {
  MethodChannelServerClient({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(serverChannelName);

  final MethodChannel _channel;

  Future<Object?> _invoke(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } on MissingPluginException {
      throw const ServerException('服务器模式仅在 Android 上可用');
    } on PlatformException catch (error) {
      throw ServerException(error.message ?? error.code);
    }
  }

  Future<Map<String, Object?>> _request(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    final raw = await _invoke('request', {
      'request': jsonEncode({'id': 1, 'method': method, 'params': params}),
    });
    final decoded = jsonDecode(raw as String? ?? '{}');
    if (decoded is! Map) throw const ServerException('控制响应格式错误');
    if (decoded['ok'] != true) {
      final error = decoded['error'];
      final message = error is Map ? error['message'] as String? : null;
      throw ServerException(message ?? '控制请求失败');
    }
    return Map<String, Object?>.from(decoded);
  }

  @override
  Future<ServerStatus> status() async =>
      ServerStatus.fromMap(await _invoke('status'));

  @override
  Future<bool> start({required bool preferRoot}) async =>
      await _invoke('start', {'preferRoot': preferRoot}) == true;

  @override
  Future<bool> stop() async => await _invoke('stop') == true;

  @override
  Future<ServerRootStatus> probeRoot() async =>
      ServerRootStatus.fromMap(await _invoke('probe_root'));

  @override
  Future<String?> readConfig() async =>
      await _invoke('read_config') as String?;

  @override
  Future<void> writeConfig(ServerConfig config) async {
    await _invoke('write_config', {'config': jsonEncode(config.toJson())});
  }

  @override
  Future<ServerConfig> getConfig() async {
    try {
      final response = await _request('get_config');
      final result = response['result'];
      if (result is Map) {
        return ServerConfig.fromJson(Map<String, Object?>.from(result));
      }
    } on ServerException {
      // A stopped server has no control socket; the file is authoritative then.
    }
    final raw = await readConfig();
    if (raw == null || raw.trim().isEmpty) return ServerConfig.defaults();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const ServerException('服务器配置格式错误');
    return ServerConfig.fromJson(Map<String, Object?>.from(decoded));
  }

  @override
  Future<ServerConfig> saveConfig(ServerConfig config) async {
    final current = await status();
    if (!current.running) {
      await writeConfig(config);
      return config;
    }
    final response = await _request('update_config', {
      'config': config.toJson(),
    });
    final result = response['result'];
    return result is Map
        ? ServerConfig.fromJson(Map<String, Object?>.from(result))
        : config;
  }

  @override
  Future<ServerStats> stats() async {
    final response = await _request('stats');
    return ServerStats.fromJson(response['result']);
  }

  @override
  Future<ServerQueryResult> queryLog(ServerLogQuery query) async {
    final response = await _request('query_log', query.toJson());
    return ServerQueryResult.fromJson(response['result']);
  }

  @override
  Future<void> clearQueryLog() async {
    await _request('clear_query_log');
  }

  @override
  Future<ServerFilterConfig> refreshFilter([String id = '']) async {
    final response = await _request('filter_refresh', {'id': id});
    final result = response['result'];
    return result is Map
        ? ServerFilterConfig.fromJson(Map<String, Object?>.from(result))
        : const ServerFilterConfig();
  }

  @override
  Future<ServerFilterCheck> filterCheck(
    String domain, {
    String qtype = 'A',
  }) async {
    final response = await _request('filter_check', {
      'domain': domain,
      'qtype': qtype,
    });
    return ServerFilterCheck.fromJson(response['result']);
  }
}
