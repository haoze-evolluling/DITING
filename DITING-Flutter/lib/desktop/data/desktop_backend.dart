import 'dart:async';
import 'dart:convert';

import 'package:diting/desktop/data/desktop_models.dart';
import 'package:http/http.dart' as http;

class DesktopBackendException implements Exception {
  const DesktopBackendException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Desktop DNS data plane. The implementation talks to the existing local Go
/// service; no DNS or filtering business rules are duplicated in Flutter.
abstract class DesktopBackend {
  Future<DesktopSnapshot> getSnapshot();
  Future<void> setDnsRunning(bool running);
  Future<void> setTakeover(bool enabled);
}

class HttpDesktopBackend implements DesktopBackend {
  HttpDesktopBackend({
    http.Client? client,
    this.token = '',
    this.baseUri = const String.fromEnvironment(
      'DITING_DESKTOP_API',
      defaultValue: 'http://127.0.0.1:15353',
    ),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String token;
  final String baseUri;
  static const _timeout = Duration(seconds: 6);

  @override
  Future<DesktopSnapshot> getSnapshot() async {
    final data = await _request('GET', '/api/v1/status');
    if (data is! Map) {
      throw const DesktopBackendException('后台服务返回了无法识别的状态数据。');
    }
    return DesktopSnapshot.fromJson(Map<String, dynamic>.from(data));
  }

  @override
  Future<void> setDnsRunning(bool running) =>
      _request('POST', running ? '/api/v1/dns/start' : '/api/v1/dns/stop');

  @override
  Future<void> setTakeover(bool enabled) => _request(
    'POST',
    enabled ? '/api/v1/takeover/enable' : '/api/v1/takeover/disable',
  );

  Future<dynamic> _request(String method, String path) async {
    try {
      final uri = Uri.parse('$baseUri$path');
      final request = http.Request(method, uri)
        ..headers['Accept'] = 'application/json';
      if (token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
        request.headers['X-API-Token'] = token;
      }
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      final body = response.body.isEmpty
          ? null
          : jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DesktopBackendException(_errorMessage(body, response.statusCode));
      }
      if (body is Map && body['success'] == false) {
        throw DesktopBackendException(_errorMessage(body, response.statusCode));
      }
      return body is Map ? body['data'] : body;
    } on DesktopBackendException {
      rethrow;
    } on TimeoutException {
      throw const DesktopBackendException('连接后台服务超时，请检查核心服务是否运行。');
    } on Object catch (error) {
      throw DesktopBackendException('无法连接本机后台服务：$error');
    }
  }

  String _errorMessage(Object? body, int statusCode) {
    if (body is Map) {
      final message = body['error'] ?? body['message'];
      if (message != null && message.toString().isNotEmpty) {
        return message.toString();
      }
    }
    return '后台服务请求失败（HTTP $statusCode）。';
  }
}
