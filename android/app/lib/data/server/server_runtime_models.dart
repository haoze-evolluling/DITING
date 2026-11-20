library;

class ServerStatus {
  const ServerStatus({
    this.running = false,
    this.starting = false,
    this.root = false,
    this.port = 1053,
    this.addresses = const [],
    this.startedAt,
    this.error,
  });

  final bool running;
  final bool starting;
  final bool root;
  final int port;
  final List<String> addresses;
  final DateTime? startedAt;
  final String? error;

  bool get active => running || starting;

  factory ServerStatus.fromMap(Object? raw) {
    final map = raw is Map ? raw : const {};
    final started = (map['startedAt'] as num?)?.toInt() ?? 0;
    return ServerStatus(
      running: map['running'] == true,
      starting: map['starting'] == true,
      root: map['root'] == true,
      port: (map['port'] as num?)?.toInt() ?? 1053,
      addresses: [
        for (final address in (map['addresses'] as List?) ?? const [])
          if (address is String) address,
      ],
      startedAt: started > 0
          ? DateTime.fromMillisecondsSinceEpoch(started)
          : null,
      error: map['error'] as String?,
    );
  }

  ServerStatus copyWith({
    bool? running,
    bool? starting,
    bool? root,
    int? port,
    List<String>? addresses,
    DateTime? startedAt,
    String? error,
    bool clearError = false,
  }) => ServerStatus(
    running: running ?? this.running,
    starting: starting ?? this.starting,
    root: root ?? this.root,
    port: port ?? this.port,
    addresses: addresses ?? this.addresses,
    startedAt: startedAt ?? this.startedAt,
    error: clearError ? null : error ?? this.error,
  );
}

class ServerRootStatus {
  const ServerRootStatus({
    required this.available,
    this.uid = -1,
    this.message = '',
  });

  final bool available;
  final int uid;
  final String message;

  factory ServerRootStatus.fromMap(Object? raw) {
    final map = raw is Map ? raw : const {};
    return ServerRootStatus(
      available: map['available'] == true,
      uid: (map['uid'] as num?)?.toInt() ?? -1,
      message: map['message'] as String? ?? '',
    );
  }
}

class ServerNameCount {
  const ServerNameCount({required this.name, required this.count});

  final String name;
  final int count;

  factory ServerNameCount.fromJson(Object? raw) {
    final map = raw is Map ? raw : const {};
    return ServerNameCount(
      name: map['name'] as String? ?? '',
      count: (map['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class ServerHourPoint {
  const ServerHourPoint({
    required this.hour,
    required this.queries,
    required this.blocked,
    required this.cached,
  });

  final DateTime hour;
  final int queries;
  final int blocked;
  final int cached;

  factory ServerHourPoint.fromJson(Object? raw) {
    final map = raw is Map ? raw : const {};
    return ServerHourPoint(
      hour: DateTime.fromMillisecondsSinceEpoch(
        (map['hourMs'] as num?)?.toInt() ?? 0,
      ),
      queries: (map['queries'] as num?)?.toInt() ?? 0,
      blocked: (map['blocked'] as num?)?.toInt() ?? 0,
      cached: (map['cached'] as num?)?.toInt() ?? 0,
    );
  }
}

class ServerStats {
  const ServerStats({
    this.queries = 0,
    this.blocked = 0,
    this.cached = 0,
    this.forwarded = 0,
    this.errors = 0,
    this.averageResponseMs = 0,
    this.blockedRate = 0,
    this.cacheHitRate = 0,
    this.perHour = const [],
    this.topDomains = const [],
    this.topBlockedDomains = const [],
    this.topClients = const [],
  });

  final int queries;
  final int blocked;
  final int cached;
  final int forwarded;
  final int errors;
  final double averageResponseMs;
  final double blockedRate;
  final double cacheHitRate;
  final List<ServerHourPoint> perHour;
  final List<ServerNameCount> topDomains;
  final List<ServerNameCount> topBlockedDomains;
  final List<ServerNameCount> topClients;

  factory ServerStats.fromJson(Object? raw) {
    final map = raw is Map ? raw : const {};
    final summary = map['summary'] is Map
        ? Map<String, Object?>.from(map['summary'] as Map)
        : const <String, Object?>{};
    int number(String key) => (summary[key] as num?)?.toInt() ?? 0;
    double decimal(String key) => (summary[key] as num?)?.toDouble() ?? 0;
    List<ServerNameCount> ranks(Object? value) => [
      for (final item in (value as List?) ?? const [])
        ServerNameCount.fromJson(item),
    ];
    return ServerStats(
      queries: number('queries'),
      blocked: number('blocked'),
      cached: number('cached'),
      forwarded: number('forwarded'),
      errors: number('errors'),
      averageResponseMs: decimal('avgResponseMs'),
      blockedRate: decimal('blockedRate'),
      cacheHitRate: decimal('cacheHitRate'),
      perHour: [
        for (final item in (map['perHour'] as List?) ?? const [])
          ServerHourPoint.fromJson(item),
      ],
      topDomains: ranks(map['topDomains']),
      topBlockedDomains: ranks(map['topBlockedDomains']),
      topClients: ranks(map['topClients']),
    );
  }
}

class ServerQueryRecord {
  const ServerQueryRecord({
    required this.timestamp,
    required this.domain,
    this.qtype = '',
    this.clientIP = '',
    this.clientName = '',
    this.durationMs = 0,
    this.rcode = '',
    this.status = 'allowed',
    this.cached = false,
    this.ttl,
    this.cacheHit = '',
    this.blocked = false,
    this.filterRule = '',
    this.filterReason = '',
    this.protocol = '',
    this.upstreamProvider = '',
    this.error = '',
  });

  final DateTime timestamp;
  final String domain;
  final String qtype;
  final String clientIP;
  final String clientName;
  final double durationMs;
  final String rcode;
  final String status;
  final bool cached;
  final int? ttl;
  final String cacheHit;
  final bool blocked;
  final String filterRule;
  final String filterReason;
  final String protocol;
  final String upstreamProvider;
  final String error;

  String get client => clientName.isNotEmpty ? clientName : clientIP;

  factory ServerQueryRecord.fromJson(Object? raw) {
    final map = raw is Map ? raw : const {};
    return ServerQueryRecord(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['ts'] as num?)?.toInt() ?? 0,
      ),
      domain: map['domain'] as String? ?? '',
      qtype: map['qtype'] as String? ?? '',
      clientIP: map['clientIP'] as String? ?? '',
      clientName: map['clientName'] as String? ?? '',
      durationMs: (map['durationMs'] as num?)?.toDouble() ?? 0,
      rcode: map['rcode'] as String? ?? '',
      status: map['status'] as String? ?? 'allowed',
      cached: map['cached'] == true,
      ttl: (map['ttl'] as num?)?.toInt(),
      cacheHit: map['cacheHit'] as String? ?? '',
      blocked: map['blocked'] == true,
      filterRule: map['filterRule'] as String? ?? '',
      filterReason: map['filterReason'] as String? ?? '',
      protocol: map['protocol'] as String? ?? '',
      upstreamProvider: map['upstreamProvider'] as String? ?? '',
      error: map['error'] as String? ?? '',
    );
  }
}

class ServerQueryResult {
  const ServerQueryResult({this.total = 0, this.entries = const []});

  final int total;
  final List<ServerQueryRecord> entries;

  factory ServerQueryResult.fromJson(Object? raw) {
    final map = raw is Map ? raw : const {};
    return ServerQueryResult(
      total: (map['total'] as num?)?.toInt() ?? 0,
      entries: [
        for (final item in (map['entries'] as List?) ?? const [])
          ServerQueryRecord.fromJson(item),
      ],
    );
  }
}

class ServerLogQuery {
  const ServerLogQuery({
    this.domain = '',
    this.client = '',
    this.status = '',
    this.limit = 50,
    this.offset = 0,
  });

  final String domain;
  final String client;
  final String status;
  final int limit;
  final int offset;

  Map<String, Object?> toJson() => {
    'domain': domain,
    'client': client,
    'status': status,
    'limit': limit,
    'offset': offset,
    'includeFile': true,
  };

  @override
  bool operator ==(Object other) =>
      other is ServerLogQuery &&
      other.domain == domain &&
      other.client == client &&
      other.status == status &&
      other.limit == limit &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(domain, client, status, limit, offset);
}

class ServerFilterCheck {
  const ServerFilterCheck({
    this.blocked = false,
    this.action = '',
    this.matchedRule = '',
    this.listName = '',
    this.reason = '',
  });

  final bool blocked;
  final String action;
  final String matchedRule;
  final String listName;
  final String reason;

  factory ServerFilterCheck.fromJson(Object? raw) {
    final map = raw is Map ? raw : const {};
    return ServerFilterCheck(
      blocked: map['blocked'] == true,
      action: map['action'] as String? ?? '',
      matchedRule: map['matchedRule'] as String? ?? '',
      listName: map['listName'] as String? ?? '',
      reason: map['reason'] as String? ?? '',
    );
  }
}
