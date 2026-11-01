/// Transport for the local service API (`Desktop/internal/ipc`), the desktop host's only data
/// source: it has no Android channels and no Wails bindings.
///
/// Nothing here decides how anything looks; it turns HTTP answers into the models in
/// `desktop_api_models.dart` and turns failures into [DesktopApiException].
library;

import 'dart:async';
import 'dart:convert';

import 'package:diting/desktop/data/api/desktop_api_models.dart';
import 'package:diting/desktop/data/api/desktop_cache_models.dart';
import 'package:diting/desktop/data/api/desktop_dns64_models.dart';
import 'package:diting/desktop/data/api/desktop_encrypted_models.dart';
import 'package:diting/desktop/data/api/desktop_filter_config_models.dart';
import 'package:diting/desktop/data/api/desktop_filter_models.dart';
import 'package:diting/desktop/data/api/desktop_privacy_models.dart';
import 'package:diting/desktop/data/api/desktop_schedule_models.dart';
import 'package:diting/desktop/data/api/desktop_services_models.dart';
import 'package:diting/desktop/data/api/desktop_traffic_models.dart';
import 'package:diting/desktop/data/api/desktop_rewrite_models.dart';
import 'package:diting/desktop/data/api/desktop_upstream_models.dart';
import 'package:diting/desktop/data/api/desktop_zone_models.dart';
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

  Future<DesktopQueryLogConfig> queryLogConfig() async =>
      DesktopQueryLogConfig.fromJson(await _get('/api/v1/querylog/config'));

  /// The service merges the body over the config it already holds, so the page sends the whole
  /// form and then re-reads rather than assuming what was applied.
  Future<void> updateQueryLogConfig(DesktopQueryLogConfig config) =>
      _post('/api/v1/querylog/config', body: config.toJson());

  /// The authoritative resolver config; `/status` only carries a summary of it.
  Future<DesktopUpstreamConfig> upstreamConfig() async =>
      DesktopUpstreamConfig.fromJson(await _get('/api/v1/upstream/configure'));

  /// The service merges the body over its current config, so the page sends the whole form and
  /// then re-reads instead of assuming what was applied.
  Future<void> updateUpstreamConfig(DesktopUpstreamConfig config) =>
      _post('/api/v1/upstream/configure', body: config.toJson());

  /// A probe answers `success: false` with the reason when the node itself failed; that is a
  /// result the page shows next to the node, not a failed request.
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

  /// Pauses rule blocking for [durationSec] (`0` means until resumed by hand), or resumes it right
  /// away. The service refuses a negative or absurdly long duration itself.
  Future<void> setFilterPaused(bool paused, {int? durationSec}) => _post(
    '/api/v1/filter/pause',
    body: {'paused': paused, if (paused) 'durationSec': durationSec ?? 0},
  );

  Future<DesktopCacheStats> cacheStats() async =>
      DesktopCacheStats.fromJson(await _get('/api/v1/cache/stats'));

  /// `query` matches the domain and the record type; the service answers with the total it counted
  /// plus at most `limit` rows.
  Future<DesktopCacheEntries> cacheEntries({
    String query = '',
    int limit = 100,
  }) async => DesktopCacheEntries.fromJson(
    await _get(
      '/api/v1/cache/entries',
      query: {'limit': '$limit', if (query.isNotEmpty) 'query': query},
    ),
  );

  /// Already ranked and capped by the service; the page neither re-sorts nor extends the list.
  Future<List<DesktopCacheDomain>> cacheTopDomains({int limit = 10}) async {
    final response = await _send(
      '/api/v1/cache/top',
      method: 'GET',
      query: {'limit': '$limit'},
    );
    return desktopCacheDomains(response['data']);
  }

  /// Drops every cached answer. The service keeps no undo, so the page asks first.
  Future<void> clearCache() => _post('/api/v1/cache/clear');

  Future<DesktopCacheConfig> cacheConfig() async =>
      DesktopCacheConfig.fromJson(await _get('/api/v1/cache/config'));

  /// The service merges the body over its current config and clamps it, so the page sends the whole
  /// form and re-reads instead of assuming what was applied.
  Future<void> updateCacheConfig(DesktopCacheConfig config) =>
      _post('/api/v1/cache/config', body: config.toJson());

  Future<DesktopCachePersist> cachePersist() async =>
      DesktopCachePersist.fromJson(await _get('/api/v1/cache/persist'));

  /// Writes the in-memory cache to disk now, and answers with the resulting status.
  Future<DesktopCachePersist> dumpCache() async =>
      DesktopCachePersist.fromJson(await _postData('/api/v1/cache/dump'));

  /// Reads the persisted file back into memory, and answers with how many entries it restored.
  Future<DesktopCachePersist> loadCache() async =>
      DesktopCachePersist.fromJson(await _postData('/api/v1/cache/load'));

  /// Reads the engine switch and default TTL from `/status` (its `rewrite` summary) and the rule
  /// list from its own endpoint: the console does the same, and the list is what an edit rewrites.
  Future<DesktopRewriteConfig> rewriteConfig() async {
    final status = await _get('/api/v1/status');
    final rewrite = status['rewrite'];
    final config = DesktopRewriteConfig.fromJson(
      rewrite is Map ? rewrite.cast<String, Object?>() : const {},
    );
    return config.copyWith(rules: await rewriteRules());
  }

  /// Every configured rule, in the service's order. The endpoint answers with a bare array.
  Future<List<DesktopRewriteRule>> rewriteRules() async {
    final envelope = await _send('/api/v1/dns/rewrite/rules', method: 'GET');
    final data = envelope['data'];
    return [
      for (final item in data is List ? data : const [])
        if (item is Map)
          DesktopRewriteRule.fromJson(item.cast<String, Object?>()),
    ];
  }

  /// The service merges the field into the current config, so one switch or one TTL never rewrites
  /// the rule list.
  Future<void> setRewriteEnabled(bool enabled) =>
      _post('/api/v1/dns/rewrite/configure', body: {'enabled': enabled});

  Future<void> setRewriteTtl(int ttl) =>
      _post('/api/v1/dns/rewrite/configure', body: {'ttl': ttl});

  /// Adds a rule or replaces the one with the same domain; the service validates the records.
  Future<void> saveRewriteRule(DesktopRewriteRule rule) =>
      _post('/api/v1/dns/rewrite/rules', body: rule.toJson());

  /// Removes the rule for [domain]. The service has no undo, so the page asks first.
  Future<void> deleteRewriteRule(String domain) async {
    await _send(
      '/api/v1/dns/rewrite/rules',
      method: 'DELETE',
      query: {'domain': domain},
    );
  }

  /// The config plus the service's build result for every zone. Saving posts the form and adopts
  /// the rebuilt state, because a zone that fails to parse still has to be visible as failing.
  Future<DesktopZoneConfig> zoneConfig() async =>
      DesktopZoneConfig.fromJson(await _get('/api/v1/dns/zone/config'));

  /// Only the fields given are changed; the answer is the rebuilt config, or null when the service
  /// saved but could not describe the result (it then asks again with [zoneConfig]).
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

  /// Runs one zone text through the engine's parser without saving it. A parse failure is an
  /// expected answer (`success: false`), not a failed request.
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

  /// Reads the synthesizer config from `/status` (its `dns64` field), like the console does.
  Future<DesktopDns64Config> dns64Config() async {
    final status = await _get('/api/v1/status');
    final dns64 = status['dns64'];
    return DesktopDns64Config.fromJson(
      dns64 is Map ? dns64.cast<String, Object?>() : const {},
    );
  }

  /// The service validates every prefix and answers with an error when one is outside RFC 6052, so
  /// the page sends the whole form and then re-reads instead of assuming it was accepted.
  Future<void> updateDns64Config(DesktopDns64Config config) =>
      _post('/api/v1/dns/dns64/configure', body: config.toJson());

  Future<DesktopFilterConfig> filterConfig() async =>
      DesktopFilterConfig.fromJson(await _get('/api/v1/filter/config'));

  /// The service merges the body over its current config, so the page sends its whole form and then
  /// re-reads instead of assuming what was applied.
  Future<void> updateFilterConfig(DesktopFilterConfig config) =>
      _post('/api/v1/filter/config', body: config.toJson());

  Future<DesktopFilterPause> filterPause() async =>
      DesktopFilterPause.fromJson(await _get('/api/v1/filter/pause'));

  /// The privacy and protocol-hardening fields `/status` carries, in one read.
  Future<DesktopPrivacyConfig> privacyConfig() async =>
      DesktopPrivacyConfig.fromJson(await _get('/api/v1/status'));

  Future<void> configurePrivacy(DesktopPrivacyConfig config) =>
      _post('/api/v1/dns/privacy/configure', body: config.privacyJson());

  Future<void> configureUnqualified(bool enabled) => _post(
    '/api/v1/dns/unqualified/configure',
    body: {'blockUnqualified': enabled},
  );

  Future<void> configureEcs(DesktopPrivacyConfig config) => _post(
    '/api/v1/dns/ecs/configure',
    body: {
      'enabled': config.ecsEnabled,
      'stripECS': config.ecsStrip,
      'customSubnet': config.ecsCustomSubnet.trim(),
    },
  );

  Future<void> configureRebind(DesktopPrivacyConfig config) => _post(
    '/api/v1/dns/rebind/configure',
    body: {
      'enabled': config.rebindEnabled,
      'allowedDomains': config.rebindAllowedDomains,
    },
  );

  Future<void> configureHosts(DesktopPrivacyConfig config) => _post(
    '/api/v1/dns/hosts/configure',
    body: {
      'enabled': config.hostsEnabled,
      'useSystemHost': config.hostsUseSystem,
      'customFiles': config.hostsCustomFiles,
      'ttl': config.hostsTtl,
    },
  );

  Future<DesktopSafeSearchConfig> safeSearch() async =>
      DesktopSafeSearchConfig.fromJson(await _get('/api/v1/safesearch/config'));

  /// The service merges the patch and answers with a success flag, so the page re-reads.
  Future<void> configureSafeSearch(Map<String, Object?> patch) =>
      _post('/api/v1/safesearch/config', body: patch);

  Future<DesktopSafeBrowsing> safeBrowsing() async =>
      DesktopSafeBrowsing.fromJson(await _get('/api/v1/filter/safebrowsing'));

  /// Answers with the normalised state (config + counters), which the page adopts directly.
  Future<DesktopSafeBrowsing> configureSafeBrowsing(
    Map<String, Object?> patch,
  ) async => DesktopSafeBrowsing.fromJson(
    await _postData('/api/v1/filter/safebrowsing', body: patch),
  );

  Future<DesktopEncryptedStatus> encryptedStatus() async =>
      DesktopEncryptedStatus.fromJson(
        await _get('/api/v1/encrypted/dns/status'),
      );

  /// The service merges the patch and answers with the normalised status.
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

  /// The mobile configuration profile is served as a file and authenticates by query token, because
  /// a device opening the link cannot send a custom header.
  Uri mobileConfigUri() => _config.uri('/api/v1/encrypted/mobileconfig', {
    if (_config.token.isNotEmpty) 'token': _config.token,
  });

  /// The built-in catalogue plus the current selection and plans.
  Future<DesktopBlockedServices> blockedServices() async =>
      DesktopBlockedServices.fromJson(
        await _get('/api/v1/filter/services'),
      );

  /// Omitted fields keep their current value; an empty list clears that dimension. The service
  /// answers with the whole new state, which the page adopts directly.
  Future<DesktopBlockedServices> configureBlockedServices(
    Map<String, Object?> body,
  ) async => DesktopBlockedServices.fromJson(
    await _postData('/api/v1/filter/services', body: body),
  );

  Future<DesktopScheduleConfig> blockingSchedule() async =>
      DesktopScheduleConfig.fromJson(await _get('/api/v1/filter/schedule'));

  /// The service validates every window's clock and weekdays; the page sends the whole list and then
  /// re-reads what it kept.
  Future<void> updateBlockingSchedule(DesktopScheduleConfig config) =>
      _post('/api/v1/filter/schedule', body: config.toJson());

  /// The counters the console shows above the subscription lists.
  Future<DesktopFilterSummary> filterStats() async =>
      DesktopFilterSummary.fromJson(await _get('/api/v1/filter/stats'));

  Future<DesktopFilterLists> filterLists() async =>
      DesktopFilterLists.fromJson(await _get('/api/v1/filter/lists'));

  /// The service refuses an empty URL; the page checks first so the dialog can say so without a
  /// round trip.
  Future<void> addFilterList({
    required String name,
    required String url,
  }) => _post(
    '/api/v1/filter/lists/add',
    body: {'name': name, 'url': url, 'enabled': true},
  );

  /// Replaces the list's name, URL and switch; the rule counters stay the service's.
  Future<void> updateFilterList(DesktopFilterList list) =>
      _post('/api/v1/filter/lists/update', body: list.toJson());

  /// Removes the list and its rules. The service has no undo, so the page asks first.
  Future<void> deleteFilterList(String id) =>
      _post('/api/v1/filter/lists/delete', body: {'id': id});

  /// Downloads one list, or every list when [id] is empty.
  Future<void> refreshFilterLists(String id) =>
      _post('/api/v1/filter/lists/refresh', body: {'id': id});

  /// The user's own rules, in the service's order. The endpoint answers with a bare array.
  Future<List<String>> customRules() async {
    final data = await _get('/api/v1/filter/rules');
    return switch (data['rules']) {
      List() => [for (final rule in data['rules'] as List) '$rule'],
      _ => const [],
    };
  }

  /// Replaces the whole list; the service rebuilds its index and answers with a success flag.
  Future<void> setCustomRules(List<String> rules) =>
      _post('/api/v1/filter/rules', body: {'rules': rules});

  /// The clients the service has seen, in its own order.
  Future<List<DesktopClient>> clients() async {
    final response = await _send('/api/v1/clients', method: 'GET');
    return desktopClients(response['data']);
  }

  /// The ACL and rate-limit blocks live inside `/status`; there is no dedicated read endpoint.
  Future<DesktopClientLimits> clientLimits() async =>
      DesktopClientLimits.fromJson(await _get('/api/v1/status'));

  /// An empty [name] clears the alias.
  Future<void> configureClientAlias({
    required String ip,
    required String name,
  }) => _post('/api/v1/clients/alias', body: {'ip': ip, 'name': name});

  Future<void> configureAccess({
    required List<String> allowedClients,
    required List<String> blockedClients,
  }) => _post(
    '/api/v1/dns/access/configure',
    body: {
      'allowedClients': allowedClients,
      'blockedClients': blockedClients,
    },
  );

  Future<void> configureRateLimit(Map<String, Object?> config) =>
      _post('/api/v1/dns/ratelimit/configure', body: config);

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

  /// A `POST` whose answer is data rather than only a success flag.
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
