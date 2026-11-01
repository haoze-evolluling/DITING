/// Transport for the local service API (`Desktop/internal/ipc`), the desktop host's only data
/// source: it has no Android channels and no Wails bindings.
///
/// Nothing here decides how anything looks; it turns HTTP answers into the models in
/// `desktop_api_models.dart` and turns failures into [DesktopApiException].
library;

import 'dart:async';
import 'dart:convert';

import 'package:diting/desktop/data/api/desktop_api_models.dart';
import 'package:http/http.dart' as http;

/// Where the desktop app finds the local service. Loopback by default; the token is only needed
/// when the service was started with one configured.
class DesktopApiConfig {
  const DesktopApiConfig({
    this.host = '127.0.0.1',
    this.port = 15353,
    this.token = '',
  });

  final String host;
  final int port;
  final String token;

  Uri uri(String path, [Map<String, String>? query]) => Uri(
    scheme: 'http',
    host: host,
    port: port,
    path: path,
    queryParameters: query,
  );
}

/// A failed request. [unauthorized] means the service answered 401: the token is missing or wrong,
/// which is a configuration problem rather than an outage.
class DesktopApiException implements Exception {
  const DesktopApiException(
    this.message, {
    this.statusCode,
    this.unauthorized = false,
  });

  final String message;
  final int? statusCode;
  final bool unauthorized;

  @override
  String toString() => message;
}

class DesktopApiClient {
  DesktopApiClient({DesktopApiConfig? config, http.Client? httpClient})
    : _config = config ?? const DesktopApiConfig(),
      _http = httpClient ?? http.Client();

  static const _timeout = Duration(seconds: 8);

  final DesktopApiConfig _config;
  final http.Client _http;

  Future<DesktopStatus> status() async =>
      DesktopStatus.fromJson(await _get('/api/v1/status'));

  Future<CoreServiceState> serviceStatus() async =>
      CoreServiceState.fromJson(await _get('/api/v1/service/status'));

  /// Newest first. `includeFile=0` keeps the read to the in-memory ring: the dashboard wants the
  /// last few queries, not a scan of the retained history on disk.
  Future<QueryLogPage> recentQueries({int limit = 8}) async =>
      QueryLogPage.fromJson(
        await _get(
          '/api/v1/querylog/search',
          query: {'limit': '$limit', 'includeFile': '0'},
        ),
      );

  /// The service's own aggregate over its 24-hour window, so the page does not add up a page of
  /// rows and call it a total.
  Future<DesktopQueryStats> queryStats() async =>
      DesktopQueryStats.fromJson(await _get('/api/v1/querylog/stats'));

  /// One page of the query log, newest first. Unlike [recentQueries] this leaves `includeFile` on:
  /// paging past the in-memory ring is the whole point of a log page, and the service only scans
  /// the retained files when the ring cannot fill the page anyway.
  Future<QueryLogPage> searchQueries({
    String domain = '',
    String client = '',
    String qtype = '',
    DesktopLogStatus status = DesktopLogStatus.all,
    int limit = 25,
    int offset = 0,
    bool includeFile = true,
  }) async => QueryLogPage.fromJson(
    await _get(
      '/api/v1/querylog/search',
      query: {
        'limit': '$limit',
        'offset': '$offset',
        'includeFile': includeFile ? '1' : '0',
        if (domain.isNotEmpty) 'domain': domain,
        if (client.isNotEmpty) 'client': client,
        if (qtype.isNotEmpty) 'qtype': qtype,
        if (status != DesktopLogStatus.all) 'status': status.apiValue,
      },
    ),
  );

  /// Deletes the retained history together with the aggregate built from it. The service has no
  /// undo, so the page asks before calling this.
  Future<void> clearQueryLog() => _post('/api/v1/querylog/clear');

  Future<void> startDns() => _post('/api/v1/dns/start');

  Future<void> stopDns() => _post('/api/v1/dns/stop');

  Future<void> setTakeover(bool enabled) =>
      _post(enabled ? '/api/v1/takeover/enable' : '/api/v1/takeover/disable');

  /// Pauses rule blocking until resumed by hand (`durationSec: 0`), or resumes it right away.
  Future<void> setFilterPaused(bool paused) => _post(
    '/api/v1/filter/pause',
    body: {'paused': paused, if (paused) 'durationSec': 0},
  );

  void close() => _http.close();

  Future<Map<String, Object?>> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await _send(path, method: 'GET', query: query);
    return _dataOf(response);
  }

  Future<void> _post(String path, {Map<String, Object?>? body}) async {
    await _send(path, method: 'POST', body: body);
  }

  Future<Map<String, Object?>> _send(
    String path, {
    required String method,
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final request = http.Request(method, _config.uri(path, query));
    request.headers['Content-Type'] = 'application/json';
    if (_config.token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer ${_config.token}';
      request.headers['X-API-Token'] = _config.token;
    }
    if (body != null) {
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(_timeout),
      ).timeout(_timeout);
    } on TimeoutException {
      throw const DesktopApiException('request timed out');
    } on http.ClientException catch (error) {
      throw DesktopApiException(error.message);
    }
    return _decode(response);
  }

  Map<String, Object?> _decode(http.Response response) {
    if (response.statusCode == 401) {
      throw const DesktopApiException(
        'unauthorized',
        statusCode: 401,
        unauthorized: true,
      );
    }
    Map<String, Object?> envelope;
    try {
      envelope = (jsonDecode(response.body) as Map).cast<String, Object?>();
    } on FormatException {
      throw DesktopApiException(
        'unreadable response',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode >= 400 || envelope['success'] == false) {
      throw DesktopApiException(
        '${envelope['error'] ?? 'HTTP ${response.statusCode}'}',
        statusCode: response.statusCode,
      );
    }
    return envelope;
  }

  /// `{"success": true, "data": ...}`; a `null` data still has to reach the parser, so it becomes
  /// an empty map rather than a second failure mode.
  Map<String, Object?> _dataOf(Map<String, Object?> envelope) {
    final data = envelope['data'];
    return data is Map ? data.cast<String, Object?>() : const {};
  }
}
