library;

export 'package:diting_desktop/data/api/desktop_api_client_auth.dart';
export 'package:diting_desktop/data/api/desktop_api_client_network.dart';
export 'package:diting_desktop/data/api/desktop_api_client_privacy.dart';
export 'package:diting_desktop/data/api/desktop_api_client_traffic.dart';

import 'dart:async';
import 'dart:convert';

import 'package:diting_desktop/data/api/desktop_api_models.dart';
import 'package:diting_desktop/data/api/desktop_cache_models.dart';
import 'package:diting_desktop/data/api/desktop_dns64_models.dart';
import 'package:diting_desktop/data/api/desktop_encrypted_models.dart';
import 'package:diting_desktop/data/api/desktop_filter_config_models.dart';
import 'package:diting_desktop/data/api/desktop_filter_models.dart';
import 'package:diting_desktop/data/api/desktop_schedule_models.dart';
import 'package:diting_desktop/data/api/desktop_services_models.dart';
import 'package:diting_desktop/data/api/desktop_rewrite_models.dart';
import 'package:diting_desktop/data/api/desktop_upstream_models.dart';
import 'package:diting_desktop/data/api/desktop_zone_models.dart';
import 'package:http/http.dart' as http;

class DesktopApiConfig {
  const DesktopApiConfig({
    this.scheme = 'http',
    this.host = '127.0.0.1',
    this.port = 15353,
    this.token = '',
  });

  final String scheme;
  final String host;
  final int port;
  final String token;

  Uri uri(String path, [Map<String, String>? query]) => Uri(
    scheme: scheme,
    host: host,
    port: port,
    path: path,
    queryParameters: query,
  );

  Uri get origin => Uri(scheme: scheme, host: host, port: port);

  Uri resolve(String pathOrUrl) =>
      origin.resolveUri(Uri.parse(pathOrUrl));
}

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
  DesktopApiClient({
    DesktopApiConfig? config,
    http.Client? httpClient,
    this.onUnauthorized,
  }) : _config = config ?? const DesktopApiConfig(),
       _http = httpClient ?? http.Client();

  final void Function()? onUnauthorized;

  static const _timeout = Duration(seconds: 8);

  final DesktopApiConfig _config;
  final http.Client _http;

  Future<DesktopStatus> status() async =>
      DesktopStatus.fromJson(await _get('/api/v1/status'));

  Future<CoreServiceState> serviceStatus() async =>
      CoreServiceState.fromJson(await _get('/api/v1/service/status'));

  Future<bool> health() async =>
      (await _send('/api/v1/health', method: 'GET'))['data'] == 'ok';

  Future<QueryLogPage> recentQueries({int limit = 8}) async =>
      QueryLogPage.fromJson(
        await _get(
          '/api/v1/querylog/search',
          query: {'limit': '$limit', 'includeFile': '0'},
        ),
      );

  Future<DesktopQueryStats> queryStats() async =>
      DesktopQueryStats.fromJson(await _get('/api/v1/querylog/stats'));

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

  Future<void> clearQueryLog() => _post('/api/v1/querylog/clear');

  Future<DesktopQueryLogConfig> queryLogConfig() async =>
      DesktopQueryLogConfig.fromJson(await _get('/api/v1/querylog/config'));

  Future<void> updateQueryLogConfig(DesktopQueryLogConfig config) =>
      _post('/api/v1/querylog/config', body: config.toJson());

  Future<DesktopUpstreamConfig> upstreamConfig() async =>
      DesktopUpstreamConfig.fromJson(await _get('/api/v1/upstream/configure'));

  Future<void> updateUpstreamConfig(DesktopUpstreamConfig config) =>
      _post('/api/v1/upstream/configure', body: config.toJson());

  Future<DesktopUpstreamProbe> testUpstream({
    required String protocol,
    required String server,
    String url = '',
  }) async {
    final data = await _postData(
      '/api/v1/upstream/test',
      body: {
        'protocol': protocol,
        'server': server,
        if (url.isNotEmpty) 'url': url,
      },
    );
    final latency = data['latencyMs'];
    return DesktopUpstreamProbe(
      latencyMs: latency is num ? latency.toDouble() : null,
      error: '${data['error'] ?? ''}'.isEmpty
          ? (data['success'] == true ? null : 'unknown error')
          : '${data['error']}',
    );
  }

  Future<DesktopStampResult> parseStamp(String stamp) async =>
      DesktopStampResult.fromJson(
        await _postData('/api/v1/upstream/stamp', body: {'stamp': stamp}),
      );

  Future<void> startDns() => _post('/api/v1/dns/start');

  Future<void> stopDns() => _post('/api/v1/dns/stop');

  Future<void> setTakeover(bool enabled) =>
      _post(enabled ? '/api/v1/takeover/enable' : '/api/v1/takeover/disable');

  Future<void> setFilterPaused(bool paused, {int? durationSec}) => _post(
    '/api/v1/filter/pause',
    body: {'paused': paused, if (paused) 'durationSec': durationSec ?? 0},
  );

  Future<DesktopCacheStats> cacheStats() async =>
      DesktopCacheStats.fromJson(await _get('/api/v1/cache/stats'));

  Future<DesktopCacheEntries> cacheEntries({
    String query = '',
    int limit = 100,
  }) async => DesktopCacheEntries.fromJson(
    await _get(
      '/api/v1/cache/entries',
      query: {'limit': '$limit', if (query.isNotEmpty) 'query': query},
    ),
  );

  Future<List<DesktopCacheDomain>> cacheTopDomains({int limit = 10}) async {
    final response = await _send(
      '/api/v1/cache/top',
      method: 'GET',
      query: {'limit': '$limit'},
    );
    return desktopCacheDomains(response['data']);
  }

  Future<void> clearCache() => _post('/api/v1/cache/clear');

  Future<DesktopCacheConfig> cacheConfig() async =>
      DesktopCacheConfig.fromJson(await _get('/api/v1/cache/config'));

  Future<void> updateCacheConfig(DesktopCacheConfig config) =>
      _post('/api/v1/cache/config', body: config.toJson());

  Future<DesktopCachePersist> cachePersist() async =>
      DesktopCachePersist.fromJson(await _get('/api/v1/cache/persist'));

  Future<DesktopCachePersist> dumpCache() async =>
      DesktopCachePersist.fromJson(await _postData('/api/v1/cache/dump'));

  Future<DesktopCachePersist> loadCache() async =>
      DesktopCachePersist.fromJson(await _postData('/api/v1/cache/load'));

  Future<DesktopRewriteConfig> rewriteConfig() async {
    final status = await _get('/api/v1/status');
    final rewrite = status['rewrite'];
    final config = DesktopRewriteConfig.fromJson(
      rewrite is Map ? rewrite.cast<String, Object?>() : const {},
    );
    return config.copyWith(rules: await rewriteRules());
  }

  Future<List<DesktopRewriteRule>> rewriteRules() async {
    final envelope = await _send('/api/v1/dns/rewrite/rules', method: 'GET');
    final data = envelope['data'];
    return [
      for (final item in data is List ? data : const [])
        if (item is Map)
          DesktopRewriteRule.fromJson(item.cast<String, Object?>()),
    ];
  }

  Future<void> setRewriteEnabled(bool enabled) =>
      _post('/api/v1/dns/rewrite/configure', body: {'enabled': enabled});

  Future<void> setRewriteTtl(int ttl) =>
      _post('/api/v1/dns/rewrite/configure', body: {'ttl': ttl});

  Future<void> saveRewriteRule(DesktopRewriteRule rule) =>
      _post('/api/v1/dns/rewrite/rules', body: rule.toJson());

  Future<void> deleteRewriteRule(String domain) async {
    await _send(
      '/api/v1/dns/rewrite/rules',
      method: 'DELETE',
      query: {'domain': domain},
    );
  }

  Future<DesktopZoneConfig> zoneConfig() async =>
      DesktopZoneConfig.fromJson(await _get('/api/v1/dns/zone/config'));

  Future<DesktopZoneConfig?> updateZoneConfig({
    bool? enabled,
    int? ttl,
    List<DesktopZoneEntry>? zones,
  }) async {
    final body = <String, Object?>{'enabled': ?enabled, 'ttl': ?ttl};
    if (zones != null) {
      body['zones'] = [for (final zone in zones) zone.toJson()];
    }
    final data = await _postData('/api/v1/dns/zone/config', body: body);
    return data.isEmpty ? null : DesktopZoneConfig.fromJson(data);
  }

  Future<DesktopZoneTest> testZone({
    required String origin,
    required String content,
    int ttl = desktopZoneDefaultTtl,
  }) async => DesktopZoneTest.fromJson(
    await _postData(
      '/api/v1/dns/zone/test',
      body: {'origin': origin, 'content': content, 'ttl': ttl},
    ),
  );

  Future<DesktopDns64Config> dns64Config() async {
    final status = await _get('/api/v1/status');
    final dns64 = status['dns64'];
    return DesktopDns64Config.fromJson(
      dns64 is Map ? dns64.cast<String, Object?>() : const {},
    );
  }

  Future<void> updateDns64Config(DesktopDns64Config config) =>
      _post('/api/v1/dns/dns64/configure', body: config.toJson());

  Future<DesktopFilterConfig> filterConfig() async =>
      DesktopFilterConfig.fromJson(await _get('/api/v1/filter/config'));

  Future<void> updateFilterConfig(DesktopFilterConfig config) =>
      _post('/api/v1/filter/config', body: config.toJson());

  Future<DesktopFilterPause> filterPause() async =>
      DesktopFilterPause.fromJson(await _get('/api/v1/filter/pause'));

  Future<DesktopEncryptedStatus> encryptedStatus() async =>
      DesktopEncryptedStatus.fromJson(
        await _get('/api/v1/encrypted/dns/status'),
      );

  Future<DesktopEncryptedStatus> configureEncryptedDns(
    Map<String, Object?> patch,
  ) async => DesktopEncryptedStatus.fromJson(
    await _postData('/api/v1/encrypted/dns/configure', body: patch),
  );

  Future<DesktopEncryptedStatus> generateEncryptedCert(
    Map<String, Object?> params,
  ) async => DesktopEncryptedStatus.fromJson(
    await _postData('/api/v1/encrypted/dns/cert/generate', body: params),
  );

  Future<DesktopEncryptedStatus> importEncryptedCert({
    required String certPem,
    required String keyPem,
  }) async => DesktopEncryptedStatus.fromJson(
    await _postData(
      '/api/v1/encrypted/dns/cert/import',
      body: {'mode': 'pem', 'certPem': certPem, 'keyPem': keyPem},
    ),
  );

  Uri mobileConfigUri() => _config.uri('/api/v1/encrypted/mobileconfig', {
    if (_config.token.isNotEmpty) 'token': _config.token,
  });

  Future<DesktopBlockedServices> blockedServices() async =>
      DesktopBlockedServices.fromJson(
        await _get('/api/v1/filter/services'),
      );

  Future<DesktopBlockedServices> configureBlockedServices(
    Map<String, Object?> body,
  ) async => DesktopBlockedServices.fromJson(
    await _postData('/api/v1/filter/services', body: body),
  );

  Future<DesktopScheduleConfig> blockingSchedule() async =>
      DesktopScheduleConfig.fromJson(await _get('/api/v1/filter/schedule'));

  Future<void> updateBlockingSchedule(DesktopScheduleConfig config) =>
      _post('/api/v1/filter/schedule', body: config.toJson());

  Future<DesktopFilterSummary> filterStats() async =>
      DesktopFilterSummary.fromJson(await _get('/api/v1/filter/stats'));

  Future<DesktopFilterLists> filterLists() async =>
      DesktopFilterLists.fromJson(await _get('/api/v1/filter/lists'));

  Future<void> addFilterList({
    required String name,
    required String url,
  }) => _post(
    '/api/v1/filter/lists/add',
    body: {'name': name, 'url': url, 'enabled': true},
  );

  Future<void> updateFilterList(DesktopFilterList list) =>
      _post('/api/v1/filter/lists/update', body: list.toJson());

  Future<void> deleteFilterList(String id) =>
      _post('/api/v1/filter/lists/delete', body: {'id': id});

  Future<void> refreshFilterLists(String id) =>
      _post('/api/v1/filter/lists/refresh', body: {'id': id});

  Future<List<String>> customRules() async {
    final data = await _get('/api/v1/filter/rules');
    return switch (data['rules']) {
      List() => [for (final rule in data['rules'] as List) '$rule'],
      _ => const [],
    };
  }

  Future<void> setCustomRules(List<String> rules) =>
      _post('/api/v1/filter/rules', body: {'rules': rules});

  Future<Map<String, Object?>> getJson(String path) => _get(path);

  Future<Object?> getData(String path) async =>
      (await _send(path, method: 'GET'))['data'];

  Future<Map<String, Object?>> postJson(
    String path, {
    Map<String, Object?>? body,
  }) => _postData(path, body: body);

  Future<Map<String, Object?>> deleteJson(
    String path, {
    Map<String, String>? query,
  }) async => _dataOf(await _send(path, method: 'DELETE', query: query));

  Future<void> postAction(String path, {Map<String, Object?>? body}) =>
      _post(path, body: body);

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

  Future<Map<String, Object?>> _postData(
    String path, {
    Map<String, Object?>? body,
  }) async => _dataOf(await _send(path, method: 'POST', body: body));

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
    final authRoute = path.startsWith('/api/v1/auth/login') ||
        path.startsWith('/api/v1/auth/setup');
    return _decode(response, notifyAuthRequired: !authRoute);
  }

  Map<String, Object?> _decode(
    http.Response response, {
    bool notifyAuthRequired = true,
  }) {
    if (response.statusCode == 401) {
      if (notifyAuthRequired) onUnauthorized?.call();
      throw DesktopApiException(
        _errorMessageOf(response) ?? 'unauthorized',
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

  String? _errorMessageOf(http.Response response) {
    try {
      final envelope = (jsonDecode(response.body) as Map).cast<String, Object?>();
      final error = envelope['error'] ?? envelope['message'];
      return error is String && error.isNotEmpty ? error : null;
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?> _dataOf(Map<String, Object?> envelope) {
    final data = envelope['data'];
    return data is Map ? data.cast<String, Object?>() : const {};
  }
}
