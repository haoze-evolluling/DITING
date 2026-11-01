/// A stand-in for the local service API, built on `package:http`'s `MockClient` so the real
/// [DesktopApiClient] and its parsing run in every desktop test.
library;

import 'dart:convert';

import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'desktop_cache_fakes.dart';
import 'desktop_rewrite_fakes.dart';
import 'desktop_zone_fakes.dart';

export 'desktop_rewrite_fakes.dart';
export 'desktop_zone_fakes.dart';

/// A JSON answer in UTF-8. `http.Response(String)` encodes as latin-1, which cannot carry the
/// Chinese names a real service returns.
http.Response utf8Json(Object? data) => http.Response.bytes(
  utf8.encode(jsonEncode(data)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

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
  bool enableEDE = true,
  bool blockPrivatePTR = true,
  bool blockUnqualified = false,
  bool blockECH = false,
  bool blockIPv6 = false,
  bool blockANY = false,
  String blockANYMode = 'notimp',
  int ednsPadding = 128,
  bool ecsEnabled = true,
  bool ecsStrip = true,
  String ecsSubnet = '',
  bool rebindEnabled = true,
  List<String> rebindAllowed = const ['localhost', '.lan'],
  bool hostsEnabled = true,
  bool hostsUseSystem = true,
  int hostsTtl = 60,
  List<String> allowedClients = const [],
  List<String> blockedClients = const [],
  bool rateLimitEnabled = false,
  double rateLimitRate = 50,
  int rateLimitBurst = 100,
  int rateLimitIpv4Prefix = 32,
  int rateLimitIpv6Prefix = 128,
  List<String> rateLimitExempt = const ['127.0.0.1', '::1'],
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
    'enableEDE': enableEDE,
    'blockPrivatePTR': blockPrivatePTR,
    'blockUnqualified': blockUnqualified,
    'blockECH': blockECH,
    'blockIPv6': blockIPv6,
    'blockANY': blockANY,
    'blockANYMode': blockANYMode,
    'ednsPadding': ednsPadding,
  },
  'ecs': {
    'enabled': ecsEnabled,
    'stripECS': ecsStrip,
    'customSubnet': ecsSubnet,
  },
  'rebind': {
    'enabled': rebindEnabled,
    'allowedDomains': rebindAllowed,
  },
  'hosts': {
    'enabled': hostsEnabled,
    'useSystemHost': hostsUseSystem,
    'customFiles': const <String>[],
    'ttl': hostsTtl,
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
  'access': {
    'allowedClients': allowedClients,
    'blockedClients': blockedClients,
  },
  'rateLimit': {
    'enabled': rateLimitEnabled,
    'rate': rateLimitRate,
    'burst': rateLimitBurst,
    'ipv4Prefix': rateLimitIpv4Prefix,
    'ipv6Prefix': rateLimitIpv6Prefix,
    'exemptIPs': rateLimitExempt,
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

/// A `GET /api/v1/upstream/configure` payload. The service returns lower-case mode and always
/// includes `fallbackOnRcode`, which the form must round-trip.
Map<String, Object?> upstreamPayload({
  String mode = 'primary_backup',
  List<Map<String, Object?>>? providers,
  bool bootstrapEnabled = true,
  List<Map<String, Object?>>? bootstrapServers,
  Map<String, String> conditionalRoutes = const {},
  List<Map<String, Object?>> fallbackProviders = const [],
  int fallbackTimeoutMs = 0,
  List<int> fallbackOnRcode = const [2, 5],
  bool fallbackOnError = true,
}) => {
  'mode': mode,
  'providers':
      providers ??
      const [
        {
          'id': 'AliDNS (DoT)',
          'protocol': 'DOT',
          'server': 'dns.alidns.com:853',
          'weight': 1,
        },
        {
          'id': 'Cloudflare (DoH)',
          'protocol': 'DOH',
          'server': 'cloudflare-dns.com',
          'url': 'https://cloudflare-dns.com/dns-query',
          'weight': 1,
          'pin': 'AA:BB',
        },
      ],
  'bootstrap': {
    'enabled': bootstrapEnabled,
    'servers':
        bootstrapServers ??
        const [
          {
            'id': 'bootstrap-1',
            'name': 'AliDNS',
            'address': '223.5.5.5:53',
            'weight': 1,
          },
          {
            'id': 'bootstrap-2',
            'name': 'DNSPod',
            'address': '119.29.29.29:53',
            'weight': 1,
          },
        ],
  },
  'conditionalRoutes': conditionalRoutes,
  'fallbackProviders': fallbackProviders,
  'fallbackTimeoutMs': fallbackTimeoutMs,
  'fallbackOnRcode': fallbackOnRcode,
  'fallbackOnError': fallbackOnError,
};

/// A `POST /api/v1/upstream/test` answer for a reachable node.
Map<String, Object?> upstreamProbePayload({
  double latencyMs = 23.5,
  String error = '',
}) => {
  'success': error.isEmpty,
  'latencyMs': error.isEmpty ? latencyMs : 0,
  if (error.isNotEmpty) 'error': error,
};

/// A `POST /api/v1/upstream/stamp` answer.
Map<String, Object?> stampPayload({
  String protocol = 'DOH',
  String server = 'dns.alidns.com',
  String url = 'https://dns.alidns.com/dns-query',
  String providerName = 'AliDNS',
  String pin = '',
}) => {
  'protocol': protocol,
  'server': server,
  'url': url,
  'providerName': providerName,
  'pin': pin,
  'protoName': 'DoH',
  'props': {'dnssec': true, 'noLog': true, 'noFilter': false},
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

/// A `GET /api/v1/status` `dns64` payload.
Map<String, Object?> dns64Payload({
  bool enabled = false,
  List<String> prefixes = const ['64:ff9b::/96'],
}) => {'enabled': enabled, 'prefixes': prefixes};

/// A `GET /api/v1/filter/stats` payload.
Map<String, Object?> filterStatsPayload({
  bool enabled = true,
  int totalRules = 2048,
  int activeLists = 3,
  int totalQueries = 12345,
  int blockedQueries = 987,
  double blockRate = 0.08,
  bool paused = false,
  int pausedRemainingSec = 0,
}) => {
  'enabled': enabled,
  'totalRules': totalRules,
  'activeLists': activeLists,
  'totalQueries': totalQueries,
  'blockedQueries': blockedQueries,
  'allowedQueries': totalQueries - blockedQueries,
  'blockRate': blockRate,
  'scheduleActive': true,
  'paused': paused,
  'pausedRemainingSec': paused ? pausedRemainingSec : 0,
};

/// A `GET /api/v1/filter/lists` payload.
Map<String, Object?> filterListsPayload({
  List<Map<String, Object?>>? lists,
}) {
  final rows =
      lists ??
      const [
        {
          'id': 'list-1',
          'name': '广告拦截通用规则',
          'url': 'https://example.com/ads.txt',
          'enabled': true,
          'rulesCount': 1200,
          'lastUpdated': 1700000000000,
          'lastStatus': 'ok',
        },
        {
          'id': 'list-2',
          'name': '本地 hosts',
          'url': 'C:\\rules\\hosts.txt',
          'enabled': false,
          'rulesCount': 48,
          'lastUpdated': 0,
          'lastStatus': 'cached',
          'lastError': 'connection refused',
        },
      ];
  return {'total': rows.length, 'lists': rows};
}

/// A `GET /api/v1/filter/config` payload: the fields the protection pages edit.
Map<String, Object?> filterConfigPayload({
  bool enabled = true,
  String blockMode = 'null_ip',
  String blockingIPv4 = '0.0.0.0',
  String blockingIPv6 = '::',
  int updateIntervalHours = 24,
  bool filterResponse = false,
  bool allowlistOnly = false,
  bool bogusNxDomain = false,
  List<String> bogusNxDomainNetworks = const [],
}) => {
  'enabled': enabled,
  'blockMode': blockMode,
  'blockingIPv4': blockingIPv4,
  'blockingIPv6': blockingIPv6,
  'customRules': const <String>[],
  'lists': const <Object>[],
  'updateIntervalHours': updateIntervalHours,
  'filterResponse': filterResponse,
  'allowlistOnly': allowlistOnly,
  'bogusNxDomain': bogusNxDomain,
  'bogusNxDomainNetworks': bogusNxDomainNetworks,
};

/// A `GET /api/v1/filter/pause` payload.
Map<String, Object?> filterPausePayload({
  bool paused = false,
  int remainingSeconds = 0,
  bool blockingEnabled = true,
}) => {
  'paused': paused,
  'remainingSeconds': paused ? remainingSeconds : 0,
  'pausedUntilMs': 0,
  'blockingEnabled': blockingEnabled,
};

/// A `GET /api/v1/filter/schedule` payload.
Map<String, Object?> schedulePayload({
  bool enabled = false,
  List<Map<String, Object?>> schedules = const [],
  bool active = true,
  String activeId = '',
}) => {
  'enabled': enabled,
  'schedules': schedules,
  'active': active,
  'activeId': activeId,
};

/// A `GET /api/v1/filter/services` payload.
Map<String, Object?> servicesPayload({
  List<Map<String, Object?>>? services,
  List<Map<String, Object?>>? groups,
  List<String> blockedIds = const ['youtube'],
  List<String> blockedGroups = const [],
  int activeRules = 2,
  Map<String, List<Map<String, Object?>>> schedules = const {},
  List<Map<String, Object?>> scheduleStates = const [],
}) {
  final catalogue =
      services ??
      const [
        {
          'id': 'douyin',
          'name': '抖音',
          'group': 'social',
          'rules': ['||douyin.com^'],
          'ruleCount': 1,
          'source': 'builtin',
        },
        {
          'id': 'youtube',
          'name': 'YouTube',
          'group': 'video',
          'rules': ['||youtube.com^', '||ytimg.com^'],
          'ruleCount': 2,
          'source': 'builtin',
        },
      ];
  final catalogueGroups =
      groups ??
      const [
        {'id': 'social', 'name': '社交', 'count': 1},
        {'id': 'video', 'name': '视频', 'count': 1},
      ];
  return {
    'services': catalogue,
    'groups': catalogueGroups,
    'blockedIds': blockedIds,
    'blockedGroups': blockedGroups,
    'activeRules': activeRules,
    'schedules': schedules,
    'scheduleStates': scheduleStates,
  };
}

/// A `GET /api/v1/safesearch/config` payload.
Map<String, Object?> safeSearchPayload({
  bool enabled = false,
  List<String> disabled = const [],
  int ttl = 300,
}) => {'enabled': enabled, 'disabled': disabled, 'ttl': ttl};

/// A `GET /api/v1/filter/safebrowsing` payload.
Map<String, Object?> safeBrowsingPayload({
  bool enabled = false,
  bool parentalEnabled = false,
  int timeoutMs = 3000,
  int cacheSize = 10000,
  int cacheTtlSeconds = 600,
  int lookups = 120,
  int blocked = 7,
  int cacheHits = 90,
  int failures = 2,
  String blockingIPv4 = '0.0.0.0',
  String blockingIPv6 = '::',
  String blockMode = 'null_ip',
}) => {
  'config': {
    'enabled': enabled,
    'parentalEnabled': parentalEnabled,
    'timeoutMs': timeoutMs,
    'cacheSize': cacheSize,
    'cacheTTLSeconds': cacheTtlSeconds,
  },
  'stats': {
    'lookups': lookups,
    'blocked': blocked,
    'cacheHits': cacheHits,
    'failures': failures,
  },
  'blockingIPv4': blockingIPv4,
  'blockingIPv6': blockingIPv6,
  'blockMode': blockMode,
};

/// A `GET /api/v1/clients` payload.
List<Map<String, Object?>> clientsPayload() => [
  {
    'ip': '192.168.1.20',
    'name': 'laptop.lan',
    'queryCount': 321,
    'lastSeen': 1700000000,
  },
  {'ip': '192.168.1.21', 'name': '', 'queryCount': 7, 'lastSeen': 0},
];

/// A `GET /api/v1/portcheck` payload.
Map<String, Object?> portCheckPayload({
  bool available = false,
  bool hasICS = true,
  bool canAutofix = true,
  String diagnostic = '53 端口被 SharedAccess 服务占用',
  List<Map<String, Object?>>? conflicts,
}) => {
  'available': available,
  'conflicts':
      conflicts ??
      (available
          ? const <Map<String, Object?>>[]
          : [
              {
                'port': 53,
                'protocol': 'UDP',
                'localAddress': '0.0.0.0:53',
                'pid': 1234,
                'processName': 'svchost.exe',
                'serviceName': 'SharedAccess',
                'isICS': true,
                'isSelf': false,
                'diagnosis': '停止 Internet Connection Sharing 后即可释放端口',
              },
            ]),
  'hasICS': hasICS,
  'canAutofix': canAutofix,
  'diagnostic': diagnostic,
};

/// A `GET /api/v1/clients/groups` payload.
Map<String, Object?> groupsPayload() => {
  'enabled': true,
  'groups': [
    {
      'id': 'kids',
      'name': '儿童设备',
      'enabled': true,
      'clients': ['192.168.1.30'],
      'ruleListIds': ['ads'],
      'blockMode': 'nxdomain',
      'upstreamIds': ['up1'],
      'scheduleEnabled': true,
      'schedules': [
        {
          'id': 'w1',
          'name': '晚间',
          'enabled': true,
          'weekdays': ['mon'],
          'start': '20:00',
          'end': '22:00',
        },
      ],
      'allowlistOnly': true,
    },
  ],
  'ruleLists': [
    {'id': 'ads', 'name': '广告拦截', 'enabled': true},
    {'id': 'mal', 'name': '恶意域名', 'enabled': false},
  ],
  'upstreams': [
    {'id': 'up1', 'protocol': 'doh', 'server': 'https://dns.example/dns-query'},
  ],
};

/// A `GET /api/v1/encrypted/dns/status` payload.
Map<String, Object?> encryptedPayload({
  bool enabled = true,
  bool dotEnabled = true,
  bool dohEnabled = true,
  bool doqEnabled = false,
  bool ddrEnabled = false,
  String listenAddress = '',
  int dotPort = 853,
  int dohPort = 443,
  int doqPort = 853,
  String dohPath = '/dns-query',
  String serverName = 'dns.lan',
  bool proxyEnabled = false,
  List<String> proxySources = const [],
  String proxyHeader = '',
  bool certLoaded = true,
  bool selfSigned = true,
  bool certExpiresSoon = false,
  bool certExpired = false,
  bool unrestrictedTrust = false,
  String dotListen = '192.168.1.10:853',
  String dohListen = '192.168.1.10:443',
}) => {
  'config': {
    'enabled': enabled,
    'dotEnabled': dotEnabled,
    'dohEnabled': dohEnabled,
    'doqEnabled': doqEnabled,
    'ddrEnabled': ddrEnabled,
    'listenAddress': listenAddress,
    'dotPort': dotPort,
    'dohPort': dohPort,
    'doqPort': doqPort,
    'dohPath': dohPath,
    'serverName': serverName,
    'cert': {
      'keyType': 'ecdsa',
      'commonName': serverName,
      'dnsNames': [serverName],
      'ipAddresses': ['192.168.1.10'],
      'validDays': 365,
    },
    'reverseProxy': {
      'enabled': proxyEnabled,
      'trustedSources': proxySources,
      'clientIpHeader': proxyHeader,
    },
  },
  'cert': {
    'source': 'self-signed',
    'subject': 'CN=$serverName',
    'issuer': 'CN=$serverName',
    'notAfter': '2027-01-01T00:00:00Z',
    'dnsNames': [serverName],
    'ipAddresses': ['192.168.1.10'],
    'daysRemaining': 300,
    'fingerprint': 'AA:BB:CC',
    'loaded': certLoaded,
    'selfSigned': selfSigned,
  },
  'certDir': 'C:/certs',
  'defaultDotPort': 853,
  'defaultDohPort': 443,
  'defaultDoqPort': 853,
  'defaultDohPath': '/dns-query',
  'dotListen': dotListen,
  'dohListen': dohListen,
  'doqListen': '',
  'dohUrls': ['https://$serverName/dns-query'],
  'unrestrictedTrust': unrestrictedTrust,
  'certExpiresSoon': certExpiresSoon,
  'certExpired': certExpired,
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
    Map<String, Object?>? upstream,
    Map<String, Object?>? probe,
    Map<String, Object?>? stamp,
    Map<String, Object?>? cacheStats,
    Map<String, Object?>? cacheConfig,
    Map<String, Object?>? cacheEntries,
    List<Map<String, Object?>>? cacheTop,
    Map<String, Object?>? cachePersist,
    Map<String, Object?>? rewrite,
    Map<String, Object?>? dns64,
    Map<String, Object?>? filterStats,
    Map<String, Object?>? filterLists,
    Map<String, Object?>? filterConfig,
    Map<String, Object?>? filterPause,
    Map<String, Object?>? schedule,
    Map<String, Object?>? services,
    Map<String, Object?>? safeSearch,
    Map<String, Object?>? safeBrowsing,
    Map<String, Object?>? encrypted,
    List<Map<String, Object?>>? clients,
    Map<String, Object?>? groups,
    Map<String, Object?>? portCheck,
    List<String>? customRules,
    Map<String, Object?>? zone,
    Map<String, Object?>? zoneTest,
    this.failAfter,
    this.statusCode = 200,
  }) : status = status ?? statusPayload(),
       service = service ?? servicePayload(),
       queryLog = queryLog ?? queryLogPayload(),
       queryStats = queryStats ?? queryStatsPayload(),
       logConfig = logConfig ?? queryLogConfigPayload(),
       upstream = upstream ?? upstreamPayload(),
       probe = probe ?? upstreamProbePayload(),
       stamp = stamp ?? stampPayload(),
       cacheStats = cacheStats ?? cacheStatsPayload(),
       cacheConfig = cacheConfig ?? cacheConfigPayload(),
       cacheEntries = cacheEntries ?? cacheEntriesPayload(),
       cacheTop = cacheTop ?? cacheTopPayload(),
       cachePersist = cachePersist ?? cachePersistPayload(),
       rewrite = rewrite ?? rewritePayload(),
       dns64 = dns64 ?? dns64Payload(),
       filterStats = filterStats ?? filterStatsPayload(),
       filterLists = filterLists ?? filterListsPayload(),
       filterConfig = filterConfig ?? filterConfigPayload(),
       filterPause = filterPause ?? filterPausePayload(),
       schedule = schedule ?? schedulePayload(),
       services = services ?? servicesPayload(),
       safeSearch = safeSearch ?? safeSearchPayload(),
       safeBrowsing = safeBrowsing ?? safeBrowsingPayload(),
       encrypted = encrypted ?? encryptedPayload(),
       clients = clients ?? clientsPayload(),
       groups = groups ?? groupsPayload(),
       portCheck = portCheck ?? portCheckPayload(),
       customRules =
           customRules ?? ['||ads.example^', '@@||safe.example^'],
       zone = zone ?? zonePayload(),
       zoneTest = zoneTest ?? zoneTestPayload();

  Map<String, Object?> status;
  Map<String, Object?> service;
  Map<String, Object?> queryLog;
  Map<String, Object?> queryStats;

  /// Mutated by a `POST /api/v1/querylog/config`, as the service merges the body it receives.
  Map<String, Object?> logConfig;

  /// Mutated by a `POST /api/v1/upstream/configure`, as the service replaces what it receives.
  Map<String, Object?> upstream;

  /// The answer `/api/v1/upstream/test` gives next.
  Map<String, Object?> probe;

  /// The answer `/api/v1/upstream/stamp` gives next.
  Map<String, Object?> stamp;

  /// The cache the service reports; `POST /cache/config` merges into [cacheConfig], and
  /// `POST /cache/clear` empties [cacheEntries] and the stats count.
  Map<String, Object?> cacheStats;
  Map<String, Object?> cacheConfig;
  Map<String, Object?> cacheEntries;
  List<Map<String, Object?>> cacheTop;
  Map<String, Object?> cachePersist;

  /// Mutated by `POST /dns/rewrite/configure` and `/dns/rewrite/rules`, as the service merges what
  /// it receives. `GET /status` carries it as its `rewrite` field.
  Map<String, Object?> rewrite;

  /// Mutated by `POST /dns/dns64/configure`; `GET /status` carries it as its `dns64` field.
  Map<String, Object?> dns64;

  /// Bodies of every DNS64 save, in order.
  final dns64Updates = <Map<String, Object?>>[];

  /// Mutated by the four filter-list writes; the counters follow `activeLists`.
  Map<String, Object?> filterStats;
  Map<String, Object?> filterLists;

  /// Bodies of every list add and update, the ids of every delete and every refresh, in order.
  final filterListAdds = <Map<String, Object?>>[];
  final filterListUpdates = <Map<String, Object?>>[];
  final filterListDeletes = <String>[];
  final filterListRefreshes = <String>[];

  /// Mutated by `POST /filter/rules`; `GET /filter/rules` answers with it.
  List<String> customRules;

  /// Bodies of every custom-rule save, in order.
  final customRuleUpdates = <List<String>>[];

  /// Mutated by `POST /filter/config`; `GET /filter/config` answers with it.
  Map<String, Object?> filterConfig;

  /// Mutated by `POST /filter/pause`; `GET /filter/pause` answers with it.
  Map<String, Object?> filterPause;

  /// Bodies of every config save and every pause call, in order.
  final filterConfigUpdates = <Map<String, Object?>>[];
  final filterPauseRequests = <Map<String, Object?>>[];

  /// Mutated by `POST /filter/schedule`; `GET /filter/schedule` answers with it.
  Map<String, Object?> schedule;

  /// Bodies of every time-plan save, in order.
  final scheduleUpdates = <Map<String, Object?>>[];

  /// Mutated by `POST /filter/services`; `GET /filter/services` answers with it.
  Map<String, Object?> services;

  /// Bodies of every service-selection save, in order.
  final servicesUpdates = <Map<String, Object?>>[];

  /// Mutated by the alias and limit saves.
  List<Map<String, Object?>> clients;

  /// Mutated by the client-group save; the service drops groups without members.
  Map<String, Object?> groups;

  /// Mutated by the port autofix.
  Map<String, Object?> portCheck;

  /// Bodies of every port autofix call, in order.
  final autofixUpdates = <Map<String, Object?>>[];

  /// Bodies of every client-group save, in order.
  final groupsUpdates = <Map<String, Object?>>[];

  /// Bodies of every client alias, ACL and rate-limit save, in order.
  final aliasUpdates = <Map<String, Object?>>[];
  final accessUpdates = <Map<String, Object?>>[];
  final rateLimitUpdates = <Map<String, Object?>>[];

  /// Mutated by the encrypted-DNS configure / certificate calls.
  Map<String, Object?> encrypted;

  /// Bodies of every encrypted-DNS save, certificate generation and import, in order.
  final encryptedUpdates = <Map<String, Object?>>[];
  final certGenerations = <Map<String, Object?>>[];
  final certImports = <Map<String, Object?>>[];

  /// Mutated by the safe-search and reputation saves.
  Map<String, Object?> safeSearch;
  Map<String, Object?> safeBrowsing;

  /// Bodies of every safe-search and reputation save, in order.
  final safeSearchUpdates = <Map<String, Object?>>[];
  final safeBrowsingUpdates = <Map<String, Object?>>[];

  /// Bodies of every privacy-side save, in order.
  final privacyUpdates = <Map<String, Object?>>[];
  final unqualifiedUpdates = <Map<String, Object?>>[];
  final ecsUpdates = <Map<String, Object?>>[];
  final rebindUpdates = <Map<String, Object?>>[];
  final hostsUpdates = <Map<String, Object?>>[];

  /// Bodies of every rewrite config save, in order.
  final rewriteConfigUpdates = <Map<String, Object?>>[];

  /// Bodies of every rule save, and the domains of every delete, in order.
  final rewriteRuleUpdates = <Map<String, Object?>>[];
  final rewriteDeletes = <String>[];

  /// Mutated by `POST /dns/zone/config`; the fake rebuilds every zone's state after each save.
  Map<String, Object?> zone;

  /// The answer `/api/v1/dns/zone/test` gives next.
  Map<String, Object?> zoneTest;

  /// Bodies of every zone config save and every zone preview, in order.
  final zoneConfigUpdates = <Map<String, Object?>>[];
  final zoneTests = <Map<String, Object?>>[];

  /// Bodies of every cache config save, in order.
  final cacheConfigUpdates = <Map<String, Object?>>[];

  /// Query parameters of every `/api/v1/cache/entries` call, in order.
  final cacheQueries = <Map<String, String>>[];

  /// How many times each cache action was called.
  int cacheClears = 0;
  int cacheDumps = 0;
  int cacheLoads = 0;

  /// Bodies of every upstream save, in order.
  final upstreamUpdates = <Map<String, Object?>>[];

  /// Bodies of every latency probe, in order.
  final probes = <Map<String, Object?>>[];

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
      if (path == '/api/v1/upstream/configure' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        upstreamUpdates.add(body);
        upstream = {...upstream, ...body};
      }
      if (path == '/api/v1/upstream/test' && request.method == 'POST') {
        probes.add((jsonDecode(request.body) as Map).cast<String, Object?>());
      }
      if (path == '/api/v1/cache/entries') {
        cacheQueries.add(request.url.queryParameters);
      }
      if (path == '/api/v1/cache/config' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        cacheConfigUpdates.add(body);
        cacheConfig = {...cacheConfig, ...body};
      }
      if (path == '/api/v1/cache/clear' && request.method == 'POST') {
        cacheClears++;
        cacheEntries = cacheEntriesPayload(total: 0, entries: const []);
        cacheStats = {...cacheStats, 'entryCount': 0};
        cacheTop = const [];
      }
      if (path == '/api/v1/cache/dump' && request.method == 'POST') {
        cacheDumps++;
        cachePersist = {
          ...cachePersist,
          'entryCount': cacheStats['entryCount'],
        };
      }
      if (path == '/api/v1/cache/load' && request.method == 'POST') {
        cacheLoads++;
        cachePersist = {...cachePersist, 'restored': 2};
      }
      if (path == '/api/v1/dns/rewrite/configure' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        rewriteConfigUpdates.add(body);
        rewrite = {...rewrite, ...body};
      }
      if (path == '/api/v1/dns/rewrite/rules' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        rewriteRuleUpdates.add(body);
        final rules = [
          for (final item in rewrite['rules'] as List? ?? const [])
            (item as Map).cast<String, Object?>(),
        ];
        final index = rules.indexWhere(
          (rule) => rule['domain'] == body['domain'],
        );
        if (index >= 0) {
          rules[index] = body;
        } else {
          rules.add(body);
        }
        rewrite = {...rewrite, 'rules': rules};
      }
      if (path == '/api/v1/dns/rewrite/rules' && request.method == 'DELETE') {
        final domain = request.url.queryParameters['domain'] ?? '';
        rewriteDeletes.add(domain);
        rewrite = {
          ...rewrite,
          'rules': [
            for (final item in rewrite['rules'] as List? ?? const [])
              if ((item as Map)['domain'] != domain)
                item.cast<String, Object?>(),
          ],
        };
      }
      if (path == '/api/v1/portcheck/autofix' && request.method == 'POST') {
        final body = request.body.isEmpty
            ? <String, Object?>{}
            : (jsonDecode(request.body) as Map).cast<String, Object?>();
        autofixUpdates.add(body);
        portCheck = portCheckPayload(available: true, hasICS: false, canAutofix: false, diagnostic: '');
      }
      if (path == '/api/v1/clients/groups' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        groupsUpdates.add(body);
        final kept = [
          for (final group in body['groups'] as List? ?? const [])
            if (group is Map &&
                (group['clients'] as List? ?? const []).isNotEmpty)
              group,
        ];
        groups = {...groups, 'enabled': body['enabled'], 'groups': kept};
      }
      if (path == '/api/v1/clients/alias' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        aliasUpdates.add(body);
        clients = [
          for (final client in clients)
            if (client['ip'] == body['ip'])
              {...client, 'name': '${body['name'] ?? ''}'}
            else
              client,
        ];
      }
      if (path == '/api/v1/dns/access/configure' &&
          request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        accessUpdates.add(body);
        status['access'] = body;
      }
      if (path == '/api/v1/dns/ratelimit/configure' &&
          request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        rateLimitUpdates.add(body);
        status['rateLimit'] = body;
      }
      if (path == '/api/v1/encrypted/dns/configure' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        encryptedUpdates.add(body);
        final config = {...(encrypted['config'] as Map? ?? const {})};
        for (final entry in body.entries) {
          if (entry.key == 'reverseProxy' && entry.value is Map) {
            config['reverseProxy'] = {
              ...(config['reverseProxy'] as Map? ?? const {}),
              ...(entry.value as Map).cast<String, Object?>(),
            };
          } else {
            config[entry.key] = entry.value;
          }
        }
        encrypted = {...encrypted, 'config': config};
      }
      if (path == '/api/v1/encrypted/dns/cert/generate' &&
          request.method == 'POST') {
        certGenerations.add(
          (jsonDecode(request.body) as Map).cast<String, Object?>(),
        );
      }
      if (path == '/api/v1/encrypted/dns/cert/import' &&
          request.method == 'POST') {
        certImports.add(
          (jsonDecode(request.body) as Map).cast<String, Object?>(),
        );
      }
      if (path == '/api/v1/safesearch/config' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        safeSearchUpdates.add(body);
        safeSearch = {...safeSearch, ...body};
      }
      if (path == '/api/v1/filter/safebrowsing' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        safeBrowsingUpdates.add(body);
        final config = {...(safeBrowsing['config'] as Map? ?? const {})};
        safeBrowsing = {
          ...safeBrowsing,
          'config': {...config, ...body},
        };
      }
      if (path == '/api/v1/dns/privacy/configure' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        privacyUpdates.add(body);
        final dns = {...(status['dns'] as Map? ?? const {})};
        if (body['blockANY'] != null) dns['blockANY'] = body['blockANY'];
        if (body['blockANYMode'] != null) {
          dns['blockANYMode'] = body['blockANYMode'];
        }
        if (body['ednsPadding'] != null) {
          dns['ednsPadding'] = body['ednsPadding'];
        }
        for (final key in [
          'enableEDE',
          'blockPrivatePTR',
          'blockIPv6',
          'blockECH',
        ]) {
          if (body[key] != null) dns[key] = body[key];
        }
        status = {...status, 'dns': dns};
      }
      if (path == '/api/v1/dns/unqualified/configure' &&
          request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        unqualifiedUpdates.add(body);
        final dns = {...(status['dns'] as Map? ?? const {})};
        dns['blockUnqualified'] = body['blockUnqualified'];
        status = {...status, 'dns': dns};
      }
      if (path == '/api/v1/dns/ecs/configure' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        ecsUpdates.add(body);
        status = {...status, 'ecs': body};
      }
      if (path == '/api/v1/dns/rebind/configure' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        rebindUpdates.add(body);
        status = {...status, 'rebind': body};
      }
      if (path == '/api/v1/dns/hosts/configure' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        hostsUpdates.add(body);
        status = {...status, 'hosts': body};
      }
      if (path == '/api/v1/filter/services' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        servicesUpdates.add(body);
        final next = {...services};
        if (body['ids'] case final List ids) next['blockedIds'] = ids;
        if (body['groups'] case final List groups) next['blockedGroups'] = groups;
        if (body['schedules'] case final Map schedules) {
          next['scheduleStates'] = [
            for (final id in schedules.keys)
              {'serviceId': id, 'hasSchedule': true, 'active': true},
          ];
        }
        services = next;
      }
      if (path == '/api/v1/filter/schedule' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        scheduleUpdates.add(body);
        schedule = {...schedule, ...body};
      }
      if (path == '/api/v1/filter/config' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        filterConfigUpdates.add(body);
        filterConfig = {...filterConfig, ...body};
        if (body.containsKey('enabled')) {
          filterStats = {...filterStats, 'enabled': body['enabled']};
        }
      }
      if (path == '/api/v1/filter/pause' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        filterPauseRequests.add(body);
        if (body['paused'] == true) {
          filterPause = filterPausePayload(
            paused: true,
            remainingSeconds: (body['durationSec'] as num?)?.toInt() ?? 0,
          );
          filterStats = {...filterStats, 'paused': true};
        } else {
          filterPause = filterPausePayload();
          filterStats = {...filterStats, 'paused': false};
        }
      }
      if (path == '/api/v1/filter/rules' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        final rules = [
          for (final rule in body['rules'] as List? ?? const []) '$rule',
        ];
        customRuleUpdates.add(rules);
        customRules = rules;
      }
      if (path == '/api/v1/filter/lists/add' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        filterListAdds.add(body);
        final rows = [
          for (final item in filterLists['lists'] as List? ?? const [])
            (item as Map).cast<String, Object?>(),
          {
            'id': 'list-${filterListAdds.length + 10}',
            ...body,
            'rulesCount': 0,
            'lastUpdated': 0,
          },
        ];
        filterLists = {'total': rows.length, 'lists': rows};
      }
      if (path == '/api/v1/filter/lists/update' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        filterListUpdates.add(body);
        final rows = [
          for (final item in filterLists['lists'] as List? ?? const [])
            if ((item as Map)['id'] == body['id'])
              {...item.cast<String, Object?>(), ...body}
            else
              item.cast<String, Object?>(),
        ];
        filterLists = {'total': rows.length, 'lists': rows};
      }
      if (path == '/api/v1/filter/lists/delete' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        final id = '${body['id'] ?? ''}';
        filterListDeletes.add(id);
        final rows = [
          for (final item in filterLists['lists'] as List? ?? const [])
            if ((item as Map)['id'] != id) item.cast<String, Object?>(),
        ];
        filterLists = {'total': rows.length, 'lists': rows};
      }
      if (path == '/api/v1/filter/lists/refresh' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        final id = '${body['id'] ?? ''}';
        filterListRefreshes.add(id);
        final rows = [
          for (final item in filterLists['lists'] as List? ?? const [])
            if (id.isEmpty || (item as Map)['id'] == id)
              {
                ...item.cast<String, Object?>(),
                'lastStatus': 'ok',
                'lastError': '',
              }
            else
              item.cast<String, Object?>(),
        ];
        filterLists = {'total': rows.length, 'lists': rows};
      }
      if (path == '/api/v1/dns/dns64/configure' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        dns64Updates.add(body);
        dns64 = {...dns64, ...body};
      }
      if (path == '/api/v1/dns/zone/config' && request.method == 'POST') {
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        zoneConfigUpdates.add(body);
        zone = zoneConfigAfter(zone, body);
      }
      if (path == '/api/v1/dns/zone/test' && request.method == 'POST') {
        zoneTests.add(
          (jsonDecode(request.body) as Map).cast<String, Object?>(),
        );
      }
      if (path == '/api/v1/status') _statusRequests++;
      final limit = failAfter;
      if (path == '/api/v1/status' &&
          limit != null &&
          _statusRequests > limit) {
        throw http.ClientException('connection refused', request.url);
      }
      if (rejectWrites &&
          (request.method == 'POST' || request.method == 'DELETE')) {
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
            'error': statusCode == 401 ? 'unauthorized' : 'HTTP $statusCode',
          }),
          statusCode,
        );
      }
      return switch (path) {
        '/api/v1/status' => http.Response(
          jsonEncode(
            apiEnvelope({...status, 'rewrite': rewrite, 'dns64': dns64}),
          ),
          200,
        ),
        '/api/v1/dns/rewrite/rules' => http.Response(
          jsonEncode(apiEnvelope(rewrite['rules'] ?? const [])),
          200,
        ),
        '/api/v1/filter/stats' => utf8Json(apiEnvelope(filterStats)),
        '/api/v1/filter/lists' => utf8Json(apiEnvelope(filterLists)),
        '/api/v1/filter/rules' => utf8Json(
          apiEnvelope({'rules': customRules}),
        ),
        '/api/v1/filter/config' => utf8Json(apiEnvelope(filterConfig)),
        '/api/v1/filter/pause' => utf8Json(apiEnvelope(filterPause)),
        '/api/v1/filter/schedule' => utf8Json(apiEnvelope(schedule)),
        '/api/v1/filter/services' => utf8Json(apiEnvelope(services)),
        '/api/v1/safesearch/config' => utf8Json(apiEnvelope(safeSearch)),
        '/api/v1/filter/safebrowsing' => utf8Json(
          apiEnvelope(safeBrowsing),
        ),
        '/api/v1/portcheck' => utf8Json(apiEnvelope(portCheck)),
        '/api/v1/clients' => utf8Json(apiEnvelope(clients)),
        '/api/v1/clients/groups' => utf8Json(apiEnvelope(groups)),
        '/api/v1/dns/access/configure' => utf8Json(apiEnvelope(null)),
        '/api/v1/dns/ratelimit/configure' => utf8Json(apiEnvelope(null)),
        '/api/v1/clients/alias' => utf8Json(apiEnvelope(null)),
        '/api/v1/encrypted/dns/status' => utf8Json(
          apiEnvelope(encrypted),
        ),
        '/api/v1/encrypted/dns/configure' => utf8Json(
          apiEnvelope(encrypted),
        ),
        '/api/v1/encrypted/dns/cert/generate' => utf8Json(
          apiEnvelope(encrypted),
        ),
        '/api/v1/encrypted/dns/cert/import' => utf8Json(
          apiEnvelope(encrypted),
        ),
        '/api/v1/dns/zone/config' => http.Response(
          jsonEncode(apiEnvelope(zone)),
          200,
        ),
        '/api/v1/dns/zone/test' => http.Response(
          jsonEncode(apiEnvelope(zoneTest)),
          200,
        ),
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
        '/api/v1/upstream/configure' => http.Response(
          jsonEncode(apiEnvelope(upstream)),
          200,
        ),
        '/api/v1/upstream/test' => http.Response(
          jsonEncode(apiEnvelope(probe)),
          200,
        ),
        '/api/v1/upstream/stamp' => http.Response(
          jsonEncode(apiEnvelope(stamp)),
          200,
        ),
        '/api/v1/cache/stats' => http.Response(
          jsonEncode(apiEnvelope(cacheStats)),
          200,
        ),
        '/api/v1/cache/entries' => http.Response(
          jsonEncode(apiEnvelope(cacheEntries)),
          200,
        ),
        '/api/v1/cache/top' => http.Response(
          jsonEncode(apiEnvelope(cacheTop)),
          200,
        ),
        '/api/v1/cache/config' => http.Response(
          jsonEncode(apiEnvelope(cacheConfig)),
          200,
        ),
        '/api/v1/cache/persist' => http.Response(
          jsonEncode(apiEnvelope(cachePersist)),
          200,
        ),
        '/api/v1/cache/dump' => http.Response(
          jsonEncode(apiEnvelope(cachePersist)),
          200,
        ),
        '/api/v1/cache/load' => http.Response(
          jsonEncode(apiEnvelope(cachePersist)),
          200,
        ),
        _ => http.Response(jsonEncode({'success': true, 'message': 'ok'}), 200),
      };
    }),
  );
}
