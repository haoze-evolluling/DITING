/// Server-mode configuration, status, statistics and query-log models.
library;

class ServerListenConfig {
  const ServerListenConfig({
    this.port = 1053,
    this.bindAddress = '0.0.0.0',
    this.root = true,
    this.lan = true,
  });

  final int port;
  final String bindAddress;
  final bool root;
  final bool lan;

  factory ServerListenConfig.fromJson(Map<String, Object?> json) =>
      ServerListenConfig(
        port: (json['port'] as num?)?.toInt() ?? 1053,
        bindAddress: json['bindAddress'] as String? ?? '0.0.0.0',
        root: json['root'] == true,
        lan: json['lan'] != false,
      );

  Map<String, Object?> toJson() => {
    'port': port,
    'bindAddress': bindAddress,
    'root': root,
    'lan': lan,
  };
}

class ServerProviderConfig {
  const ServerProviderConfig({
    required this.id,
    required this.protocol,
    this.server = '',
    this.url = '',
    this.weight = 0,
    this.pin = '',
  });

  final String id;
  final String protocol;
  final String server;
  final String url;
  final int weight;
  final String pin;

  String get address => protocol == 'DOH' || protocol == 'DOH3' ? url : server;

  factory ServerProviderConfig.fromJson(Map<String, Object?> json) =>
      ServerProviderConfig(
        id: json['id'] as String? ?? '',
        protocol: _serverProtocol(json['protocol'] as String?),
        server: json['server'] as String? ?? '',
        url: json['url'] as String? ?? '',
        weight: (json['weight'] as num?)?.toInt() ?? 0,
        pin: json['pin'] as String? ?? '',
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'protocol': protocol,
    'server': server,
    'url': url,
    if (weight != 0) 'weight': weight,
    if (pin.isNotEmpty) 'pin': pin,
  };
}

String _serverProtocol(String? raw) {
  final upper = (raw ?? 'PLAIN').trim().toUpperCase();
  if (upper.isEmpty || upper == 'DNS') return 'PLAIN';
  return upper;
}

class ServerBootstrapConfig {
  const ServerBootstrapConfig({
    required this.id,
    required this.name,
    required this.address,
    this.weight = 1,
  });

  final String id;
  final String name;
  final String address;
  final double weight;

  factory ServerBootstrapConfig.fromJson(Map<String, Object?> json) =>
      ServerBootstrapConfig(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        address: json['address'] as String? ?? '',
        weight: (json['weight'] as num?)?.toDouble() ?? 1,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'weight': weight,
  };
}

class ServerUpstreamConfig {
  const ServerUpstreamConfig({
    this.mode = 'primary_backup',
    this.providers = const [],
    this.bootstrap = const [],
    this.bootstrapEnabled = true,
  });

  final String mode;
  final List<ServerProviderConfig> providers;
  final List<ServerBootstrapConfig> bootstrap;
  final bool bootstrapEnabled;

  factory ServerUpstreamConfig.fromJson(Map<String, Object?> json) {
    final bootstrap = json['bootstrap'];
    final bootstrapMap = bootstrap is Map ? bootstrap : const {};
    return ServerUpstreamConfig(
      mode: json['mode'] as String? ?? 'primary_backup',
      providers: [
        for (final item in (json['providers'] as List?) ?? const [])
          if (item is Map)
            ServerProviderConfig.fromJson(Map<String, Object?>.from(item)),
      ],
      bootstrap: [
        for (final item in (bootstrapMap['servers'] as List?) ?? const [])
          if (item is Map)
            ServerBootstrapConfig.fromJson(Map<String, Object?>.from(item)),
      ],
      bootstrapEnabled: bootstrapMap['enabled'] != false,
    );
  }

  Map<String, Object?> toJson() => {
    'mode': mode,
    'providers': [for (final provider in providers) provider.toJson()],
    'bootstrap': {
      'enabled': bootstrapEnabled,
      'servers': [for (final item in bootstrap) item.toJson()],
    },
  };

  ServerUpstreamConfig copyWith({
    String? mode,
    List<ServerProviderConfig>? providers,
    List<ServerBootstrapConfig>? bootstrap,
    bool? bootstrapEnabled,
  }) => ServerUpstreamConfig(
    mode: mode ?? this.mode,
    providers: providers ?? this.providers,
    bootstrap: bootstrap ?? this.bootstrap,
    bootstrapEnabled: bootstrapEnabled ?? this.bootstrapEnabled,
  );
}

class ServerFilterList {
  const ServerFilterList({
    required this.id,
    required this.name,
    required this.url,
    this.enabled = true,
    this.rulesCount = 0,
    this.lastUpdated = 0,
    this.lastStatus = '',
    this.lastError = '',
  });

  final String id;
  final String name;
  final String url;
  final bool enabled;
  final int rulesCount;
  final int lastUpdated;
  final String lastStatus;
  final String lastError;

  factory ServerFilterList.fromJson(Map<String, Object?> json) =>
      ServerFilterList(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        enabled: json['enabled'] != false,
        rulesCount: (json['rulesCount'] as num?)?.toInt() ?? 0,
        lastUpdated: (json['lastUpdated'] as num?)?.toInt() ?? 0,
        lastStatus: json['lastStatus'] as String? ?? '',
        lastError: json['lastError'] as String? ?? '',
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'enabled': enabled,
    'rulesCount': rulesCount,
    'lastUpdated': lastUpdated,
    if (lastStatus.isNotEmpty) 'lastStatus': lastStatus,
    if (lastError.isNotEmpty) 'lastError': lastError,
  };
}

class ServerFilterConfig {
  const ServerFilterConfig({
    this.enabled = true,
    this.blockMode = 'null_ip',
    this.blockingIPv4 = '0.0.0.0',
    this.blockingIPv6 = '::',
    this.customRules = const [],
    this.lists = const [],
    this.updateIntervalHours = 24,
    this.filterResponse = false,
  });

  final bool enabled;
  final String blockMode;
  final String blockingIPv4;
  final String blockingIPv6;
  final List<String> customRules;
  final List<ServerFilterList> lists;
  final int updateIntervalHours;
  final bool filterResponse;

  factory ServerFilterConfig.fromJson(Map<String, Object?> json) =>
      ServerFilterConfig(
        enabled: json['enabled'] != false,
        blockMode: json['blockMode'] as String? ?? 'null_ip',
        blockingIPv4: json['blockingIPv4'] as String? ?? '0.0.0.0',
        blockingIPv6: json['blockingIPv6'] as String? ?? '::',
        customRules: [
          for (final rule in (json['customRules'] as List?) ?? const [])
            if (rule is String) rule,
        ],
        lists: [
          for (final item in (json['lists'] as List?) ?? const [])
            if (item is Map)
              ServerFilterList.fromJson(Map<String, Object?>.from(item)),
        ],
        updateIntervalHours:
            (json['updateIntervalHours'] as num?)?.toInt() ?? 24,
        filterResponse: json['filterResponse'] == true,
      );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'blockMode': blockMode,
    'blockingIPv4': blockingIPv4,
    'blockingIPv6': blockingIPv6,
    'customRules': customRules,
    'lists': [for (final list in lists) list.toJson()],
    'updateIntervalHours': updateIntervalHours,
    'filterResponse': filterResponse,
  };

  ServerFilterConfig copyWith({
    bool? enabled,
    String? blockMode,
    String? blockingIPv4,
    String? blockingIPv6,
    List<String>? customRules,
    List<ServerFilterList>? lists,
    int? updateIntervalHours,
    bool? filterResponse,
  }) => ServerFilterConfig(
    enabled: enabled ?? this.enabled,
    blockMode: blockMode ?? this.blockMode,
    blockingIPv4: blockingIPv4 ?? this.blockingIPv4,
    blockingIPv6: blockingIPv6 ?? this.blockingIPv6,
    customRules: customRules ?? this.customRules,
    lists: lists ?? this.lists,
    updateIntervalHours: updateIntervalHours ?? this.updateIntervalHours,
    filterResponse: filterResponse ?? this.filterResponse,
  );
}

class ServerCacheConfig {
  const ServerCacheConfig({
    this.enabled = true,
    this.maxEntries = 4096,
    this.mode = 'limit_max_ttl',
    this.maxTtlSeconds = 3600,
    this.fixedTtlSeconds = 3600,
    this.minTtlEnabled = true,
    this.minTtlSeconds = 60,
    this.staleFallbackEnabled = true,
    this.staleFallbackSeconds = 300,
    this.negativeTtlEnabled = true,
    this.negativeTtlSeconds = 30,
    this.optimistic = true,
    this.prefetchEnabled = false,
  });

  final bool enabled;
  final int maxEntries;
  final String mode;
  final int maxTtlSeconds;
  final int fixedTtlSeconds;
  final bool minTtlEnabled;
  final int minTtlSeconds;
  final bool staleFallbackEnabled;
  final int staleFallbackSeconds;
  final bool negativeTtlEnabled;
  final int negativeTtlSeconds;
  final bool optimistic;
  final bool prefetchEnabled;

  factory ServerCacheConfig.fromJson(Map<String, Object?> json) =>
      ServerCacheConfig(
        enabled: json['enabled'] != false,
        maxEntries: (json['maxEntries'] as num?)?.toInt() ?? 4096,
        mode: json['mode'] as String? ?? 'limit_max_ttl',
        maxTtlSeconds: (json['maxTtlSeconds'] as num?)?.toInt() ?? 3600,
        fixedTtlSeconds: (json['fixedTtlSeconds'] as num?)?.toInt() ?? 3600,
        minTtlEnabled: json['minTtlEnabled'] != false,
        minTtlSeconds: (json['minTtlSeconds'] as num?)?.toInt() ?? 60,
        staleFallbackEnabled: json['staleFallbackEnabled'] != false,
        staleFallbackSeconds:
            (json['staleFallbackSeconds'] as num?)?.toInt() ?? 300,
        negativeTtlEnabled: json['negativeTtlEnabled'] != false,
        negativeTtlSeconds: (json['negativeTtlSeconds'] as num?)?.toInt() ?? 30,
        optimistic: json['optimistic'] != false,
        prefetchEnabled: json['prefetchEnabled'] == true,
      );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'maxEntries': maxEntries,
    'mode': mode,
    'maxTtlSeconds': maxTtlSeconds,
    'fixedTtlSeconds': fixedTtlSeconds,
    'minTtlEnabled': minTtlEnabled,
    'minTtlSeconds': minTtlSeconds,
    'staleFallbackEnabled': staleFallbackEnabled,
    'staleFallbackSeconds': staleFallbackSeconds,
    'negativeTtlEnabled': negativeTtlEnabled,
    'negativeTtlSeconds': negativeTtlSeconds,
    'optimistic': optimistic,
    'prefetchEnabled': prefetchEnabled,
  };

  ServerCacheConfig copyWith({
    bool? enabled,
    int? maxEntries,
    String? mode,
    int? maxTtlSeconds,
    int? fixedTtlSeconds,
    bool? minTtlEnabled,
    int? minTtlSeconds,
    bool? staleFallbackEnabled,
    int? staleFallbackSeconds,
    bool? negativeTtlEnabled,
    int? negativeTtlSeconds,
    bool? optimistic,
    bool? prefetchEnabled,
  }) => ServerCacheConfig(
    enabled: enabled ?? this.enabled,
    maxEntries: maxEntries ?? this.maxEntries,
    mode: mode ?? this.mode,
    maxTtlSeconds: maxTtlSeconds ?? this.maxTtlSeconds,
    fixedTtlSeconds: fixedTtlSeconds ?? this.fixedTtlSeconds,
    minTtlEnabled: minTtlEnabled ?? this.minTtlEnabled,
    minTtlSeconds: minTtlSeconds ?? this.minTtlSeconds,
    staleFallbackEnabled: staleFallbackEnabled ?? this.staleFallbackEnabled,
    staleFallbackSeconds: staleFallbackSeconds ?? this.staleFallbackSeconds,
    negativeTtlEnabled: negativeTtlEnabled ?? this.negativeTtlEnabled,
    negativeTtlSeconds: negativeTtlSeconds ?? this.negativeTtlSeconds,
    optimistic: optimistic ?? this.optimistic,
    prefetchEnabled: prefetchEnabled ?? this.prefetchEnabled,
  );
}

class ServerQueryLogConfig {
  const ServerQueryLogConfig({
    this.enabled = true,
    this.maxEntries = 10000,
    this.fileEnabled = true,
    this.retentionDays = 7,
    this.logClients = true,
  });

  final bool enabled;
  final int maxEntries;
  final bool fileEnabled;
  final int retentionDays;
  final bool logClients;

  factory ServerQueryLogConfig.fromJson(Map<String, Object?> json) =>
      ServerQueryLogConfig(
        enabled: json['enabled'] != false,
        maxEntries: (json['maxEntries'] as num?)?.toInt() ?? 10000,
        fileEnabled: json['fileEnabled'] != false,
        retentionDays: (json['retentionDays'] as num?)?.toInt() ?? 7,
        logClients: json['logClients'] != false,
      );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'maxEntries': maxEntries,
    'fileEnabled': fileEnabled,
    'retentionDays': retentionDays,
    'logClients': logClients,
  };

  ServerQueryLogConfig copyWith({
    bool? enabled,
    int? maxEntries,
    bool? fileEnabled,
    int? retentionDays,
    bool? logClients,
  }) => ServerQueryLogConfig(
    enabled: enabled ?? this.enabled,
    maxEntries: maxEntries ?? this.maxEntries,
    fileEnabled: fileEnabled ?? this.fileEnabled,
    retentionDays: retentionDays ?? this.retentionDays,
    logClients: logClients ?? this.logClients,
  );
}

class ServerConfig {
  const ServerConfig({
    this.listen = const ServerListenConfig(),
    this.upstream = const ServerUpstreamConfig(),
    this.filter = const ServerFilterConfig(),
    this.cache = const ServerCacheConfig(),
    this.queryLog = const ServerQueryLogConfig(),
  });

  final ServerListenConfig listen;
  final ServerUpstreamConfig upstream;
  final ServerFilterConfig filter;
  final ServerCacheConfig cache;
  final ServerQueryLogConfig queryLog;

  factory ServerConfig.defaults() => ServerConfig(
    upstream: const ServerUpstreamConfig(
      providers: [
        ServerProviderConfig(
          id: '阿里云 (DNS)',
          protocol: 'PLAIN',
          server: '223.5.5.5:53',
        ),
        ServerProviderConfig(
          id: '腾讯云 (DNS)',
          protocol: 'PLAIN',
          server: '119.29.29.29:53',
        ),
      ],
      bootstrap: [
        ServerBootstrapConfig(
          id: 'preset_volcengine',
          name: '火山引擎',
          address: '180.184.1.1',
        ),
        ServerBootstrapConfig(
          id: 'preset_dnspod',
          name: '腾讯云',
          address: '119.29.29.29',
        ),
        ServerBootstrapConfig(
          id: 'preset_alidns',
          name: '阿里云',
          address: '223.5.5.5',
        ),
      ],
    ),
  );

  factory ServerConfig.fromJson(Map<String, Object?> json) => ServerConfig(
    listen: ServerListenConfig.fromJson(
      Map<String, Object?>.from(json['listen'] as Map? ?? const {}),
    ),
    upstream: ServerUpstreamConfig.fromJson(
      Map<String, Object?>.from(json['upstream'] as Map? ?? const {}),
    ),
    filter: ServerFilterConfig.fromJson(
      Map<String, Object?>.from(json['filter'] as Map? ?? const {}),
    ),
    cache: ServerCacheConfig.fromJson(
      Map<String, Object?>.from(json['cache'] as Map? ?? const {}),
    ),
    queryLog: ServerQueryLogConfig.fromJson(
      Map<String, Object?>.from(
        (json['queryLog'] ?? json['querylog']) as Map? ?? const {},
      ),
    ),
  );

  Map<String, Object?> toJson() => {
    'listen': listen.toJson(),
    'upstream': upstream.toJson(),
    'filter': filter.toJson(),
    'cache': cache.toJson(),
    'queryLog': queryLog.toJson(),
  };

  ServerConfig copyWith({
    ServerListenConfig? listen,
    ServerUpstreamConfig? upstream,
    ServerFilterConfig? filter,
    ServerCacheConfig? cache,
    ServerQueryLogConfig? queryLog,
  }) => ServerConfig(
    listen: listen ?? this.listen,
    upstream: upstream ?? this.upstream,
    filter: filter ?? this.filter,
    cache: cache ?? this.cache,
    queryLog: queryLog ?? this.queryLog,
  );
}
