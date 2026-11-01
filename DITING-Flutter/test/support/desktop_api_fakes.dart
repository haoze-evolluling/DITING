/// A stand-in for the local service API, built on `package:http`'s `MockClient` so the real
/// [DesktopApiClient] and its parsing run in every desktop test.
library;

import 'dart:convert';

import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Envelope the service uses for every answer.
Map<String, Object?> apiEnvelope(Object? data) => {
  'success': true,
  'data': data,
};

/// A `GET /api/v1/status` payload. Every value can be overridden, so a test states only the fields
/// it asserts on.
Map<String, Object?> statusPayload({
  String version = '2.2.9',
  int pid = 4242,
  int uptimeSeconds = 90061,
  bool dnsRunning = true,
  List<String> listenAddresses = const ['127.0.0.1:5353'],
  bool allowLan = true,
  bool takeover = true,
  int totalQueries = 12345,
  int successQueries = 12000,
  int failedQueries = 345,
  double avgLatencyMs = 12.4,
  double qps = 7.5,
  bool cacheEnabled = true,
  int cacheHits = 8000,
  int cacheMisses = 4000,
  double hitRatio = 0.6667,
  int cacheEntries = 640,
  int cacheMaxEntries = 4096,
  int cacheEvictions = 12,
  int filterRules = 2048,
  int filterActiveLists = 3,
  int filterQueries = 12345,
  int blockedQueries = 987,
  double blockRate = 0.08,
  bool filterPaused = false,
}) => {
  'version': version,
  'pid': pid,
  'uptimeSeconds': uptimeSeconds,
  'dns': {
    'running': dnsRunning,
    'listenAddresses': listenAddresses,
    'allowLAN': allowLan,
    'lanAddresses': allowLan ? const ['192.168.1.10'] : const <String>[],
    'mode': 'normal',
  },
  'takeover': {
    'active': takeover,
    'adapters': takeover
        ? const [
            {'id': 'eth0'},
          ]
        : const <Object>[],
  },
  'metrics': {
    'totalQueries': totalQueries,
    'successQueries': successQueries,
    'failedQueries': failedQueries,
    'avgLatencyMs': avgLatencyMs,
    'qps': qps,
  },
  'cache': {
    'enabled': cacheEnabled,
    'totalHits': cacheHits,
    'totalMisses': cacheMisses,
    'hitRatio': hitRatio,
    'entryCount': cacheEntries,
    'maxEntries': cacheMaxEntries,
    'evictionCount': cacheEvictions,
  },
  'filter': {
    'enabled': true,
    'totalRules': filterRules,
    'activeLists': filterActiveLists,
    'totalQueries': filterQueries,
    'blockedQueries': blockedQueries,
    'allowedQueries': filterQueries - blockedQueries,
    'blockRate': blockRate,
    'paused': filterPaused,
    'pausedRemainingSec': filterPaused ? 600 : 0,
  },
};

/// A `GET /api/v1/querylog/search` payload with the newest entry first.
Map<String, Object?> queryLogPayload({int count = 3}) => {
  'total': count,
  'entries': [
    for (var index = 0; index < count; index++)
      {
        'ts': 1700000000000 + index * 1000,
        'domain': 'example${index + 1}.com.',
        'qtype': 'A',
        'clientIP': '127.0.0.1',
        'clientName': index == 0 ? 'laptop' : '',
        'durationMs': 4.5 + index,
        'status': index == 1 ? 'blocked' : (index == 2 ? 'cached' : 'allowed'),
        'blocked': index == 1,
        'cached': index == 2,
      },
  ],
};

/// A `GET /api/v1/querylog/stats` payload: the service's 24-hour rolling window.
Map<String, Object?> queryStatsPayload({
  int queries = 12345,
  int blocked = 987,
  int cached = 8000,
  int forwarded = 3000,
  int errors = 12,
  double avgResponseMs = 12.4,
  double cacheHitRate = 0.648,
  List<Map<String, Object?>> topDomains = const [],
  List<Map<String, Object?>> topBlocked = const [],
  List<Map<String, Object?>> topClients = const [],
}) => {
  'summary': {
    'queries': queries,
    'blocked': blocked,
    'cached': cached,
    'forwarded': forwarded,
    'errors': errors,
    'avgResponseMs': avgResponseMs,
    'cacheHitRate': cacheHitRate,
  },
  'perHour': const [],
  'topDomains': topDomains,
  'topBlocked': topBlocked,
  'topClients': topClients,
};

/// A `GET /api/v1/querylog/config` payload.
Map<String, Object?> queryLogConfigPayload({
  bool enabled = true,
  int maxEntries = 10000,
  bool fileEnabled = true,
  int retentionDays = 7,
  bool logClients = true,
  String dataDir = r'C:\ProgramData\DITING\logs',
}) => {
  'enabled': enabled,
  'maxEntries': maxEntries,
  'fileEnabled': fileEnabled,
  'retentionDays': retentionDays,
  'logClients': logClients,
  'dataDir': dataDir,
};

Map<String, Object?> servicePayload({
  bool installed = true,
  bool running = true,
  bool? autoStart = true,
}) => {
  'installed': installed,
  'running': running,
  'state': running ? 'running' : 'stopped',
  'stateText': running ? 'running' : 'stopped',
  'autoStart': autoStart == null ? null : {'enabled': autoStart},
};

/// Records the paths it was asked for, and can be told to fail after [failAfter] requests to model
/// a service that drops while the window is open.
class FakeDesktopBackend {
  FakeDesktopBackend({
    Map<String, Object?>? status,
    Map<String, Object?>? service,
    Map<String, Object?>? queryLog,
    Map<String, Object?>? queryStats,
    Map<String, Object?>? logConfig,
    this.failAfter,
    this.statusCode = 200,
  }) : status = status ?? statusPayload(),
       service = service ?? servicePayload(),
       queryLog = queryLog ?? queryLogPayload(),
       queryStats = queryStats ?? queryStatsPayload(),
       logConfig = logConfig ?? queryLogConfigPayload();

  Map<String, Object?> status;
  Map<String, Object?> service;
  Map<String, Object?> queryLog;
  Map<String, Object?> queryStats;

  /// Mutated by a `POST /api/v1/querylog/config`, as the service merges the body it receives.
  Map<String, Object?> logConfig;

  /// Bodies of every config update, so a test can assert what the page sent rather than what it
  /// then re-read.
  final configUpdates = <Map<String, Object?>>[];

  /// Number of `/api/v1/status` answers that succeed before every later one fails; null never
  /// fails. Counting only the snapshot keeps a test from depending on how many other reads the
  /// dashboard happens to issue.
  int? failAfter;

  /// Applied to every answer, so a 401 test does not need a different fake.
  int statusCode;

  /// When set, every POST is refused while reads keep working: a write the service rejected must
  /// be reported, not assumed.
  bool rejectWrites = false;

  final requests = <String>[];

  /// Query parameters of every `/api/v1/querylog/search` call, in order, so a test can assert what
  /// the page actually asked for rather than how it laid it out.
  final searches = <Map<String, String>>[];

  int _statusRequests = 0;

  int get writeCount =>
      requests.where((path) => !path.startsWith('/api/v1/status')).length;

  bool has(String path) => requests.contains(path);

  Map<String, String> get lastSearch => searches.last;

  DesktopApiClient client() => DesktopApiClient(
    httpClient: MockClient((request) async {
      final path = request.url.path;
      requests.add(path);
      if (path == '/api/v1/querylog/search') {
        searches.add(request.url.queryParameters);
      }
      if (path == '/api/v1/querylog/config' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        configUpdates.add(body);
        logConfig = {...logConfig, ...body};
      }
      if (path == '/api/v1/status') _statusRequests++;
      final limit = failAfter;
      if (path == '/api/v1/status' &&
          limit != null &&
          _statusRequests > limit) {
        throw http.ClientException('connection refused', request.url);
      }
      if (rejectWrites && request.method == 'POST') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({'success': false, 'error': 'write rejected'}),
          ),
          500,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (statusCode >= 400) {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': statusCode == 401
                ? 'unauthorized'
                : 'HTTP $statusCode',
          }),
          statusCode,
        );
      }
      return switch (path) {
        '/api/v1/status' => http.Response(jsonEncode(apiEnvelope(status)), 200),
        '/api/v1/service/status' => http.Response(
          jsonEncode(apiEnvelope(service)),
          200,
        ),
        '/api/v1/querylog/search' => http.Response(
          jsonEncode(apiEnvelope(queryLog)),
          200,
        ),
        '/api/v1/querylog/stats' => http.Response(
          jsonEncode(apiEnvelope(queryStats)),
          200,
        ),
        '/api/v1/querylog/config' => http.Response(
          jsonEncode(apiEnvelope(logConfig)),
          200,
        ),
        _ => http.Response(jsonEncode({'success': true, 'message': 'ok'}), 200),
      };
    }),
  );
}
