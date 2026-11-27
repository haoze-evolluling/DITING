library;

part 'server_settings_models.dart';

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

  String get address => protocol == 'DOH' ? url : server;

  factory ServerProviderConfig.fromJson(Map<String, Object?> json) =>
      ServerProviderConfig(
        id: json['id'] as String? ?? '',
        protocol: (json['protocol'] as String? ?? 'PLAIN').toUpperCase(),
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
    this.group = '',
    this.kind = 'all',
    this.sourceType = 'remote',
    this.mirrorTemplate = '',
    this.mirrorUrl = '',
    this.mirrorFallback = true,
  });

  final String id;
  final String name;
  final String url;
  final bool enabled;
  final int rulesCount;
  final int lastUpdated;
  final String lastStatus;
  final String lastError;

  /// 分组名；空串表示未分组。
  final String group;

  /// `all`、`domain` 或 `hosts`；旧订阅缺失时为 `all`。
  final String kind;

  /// `remote` 或 `local`。
  final String sourceType;
  final String mirrorTemplate;

  /// 已按模板展开的镜像地址，下载时由服务器优先请求。
  final String mirrorUrl;
  final bool mirrorFallback;

  bool get isRemote => sourceType != 'local';
  bool get isHosts => kind == 'hosts';
  bool get isAllKinds => kind == 'all';
  bool get hasError => lastError.isNotEmpty;
  bool get isCached => lastStatus == 'cached';

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
        group: json['group'] as String? ?? '',
        kind: json['kind'] as String? ?? 'all',
        sourceType: json['sourceType'] as String? ?? 'remote',
        mirrorTemplate: json['mirrorTemplate'] as String? ?? '',
        mirrorUrl: json['mirrorUrl'] as String? ?? '',
        mirrorFallback: json['mirrorFallback'] != false,
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
    if (group.isNotEmpty) 'group': group,
    if (kind != 'all') 'kind': kind,
    if (sourceType != 'remote') 'sourceType': sourceType,
    if (mirrorTemplate.isNotEmpty) 'mirrorTemplate': mirrorTemplate,
    if (mirrorUrl.isNotEmpty) 'mirrorUrl': mirrorUrl,
    if (!mirrorFallback) 'mirrorFallback': false,
  };

  ServerFilterList copyWith({
    String? id,
    String? name,
    String? url,
    bool? enabled,
    int? rulesCount,
    int? lastUpdated,
    String? lastStatus,
    String? lastError,
    String? group,
    String? kind,
    String? sourceType,
    String? mirrorTemplate,
    String? mirrorUrl,
    bool? mirrorFallback,
  }) => ServerFilterList(
    id: id ?? this.id,
    name: name ?? this.name,
    url: url ?? this.url,
    enabled: enabled ?? this.enabled,
    rulesCount: rulesCount ?? this.rulesCount,
    lastUpdated: lastUpdated ?? this.lastUpdated,
    lastStatus: lastStatus ?? this.lastStatus,
    lastError: lastError ?? this.lastError,
    group: group ?? this.group,
    kind: kind ?? this.kind,
    sourceType: sourceType ?? this.sourceType,
    mirrorTemplate: mirrorTemplate ?? this.mirrorTemplate,
    mirrorUrl: mirrorUrl ?? this.mirrorUrl,
    mirrorFallback: mirrorFallback ?? this.mirrorFallback,
  );
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
    this.autoUpdate = true,
    this.filterResponse = false,
  });

  final bool enabled;
  final String blockMode;
  final String blockingIPv4;
  final String blockingIPv6;
  final List<String> customRules;
  final List<ServerFilterList> lists;
  final int updateIntervalHours;
  final bool autoUpdate;
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
        autoUpdate: json['autoUpdate'] != false,
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
    'autoUpdate': autoUpdate,
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
    bool? autoUpdate,
    bool? filterResponse,
  }) => ServerFilterConfig(
    enabled: enabled ?? this.enabled,
    blockMode: blockMode ?? this.blockMode,
    blockingIPv4: blockingIPv4 ?? this.blockingIPv4,
    blockingIPv6: blockingIPv6 ?? this.blockingIPv6,
    customRules: customRules ?? this.customRules,
    lists: lists ?? this.lists,
    updateIntervalHours: updateIntervalHours ?? this.updateIntervalHours,
    autoUpdate: autoUpdate ?? this.autoUpdate,
    filterResponse: filterResponse ?? this.filterResponse,
  );
}

class ServerConfig {
  const ServerConfig({
    this.listen = const ServerListenConfig(),
    this.upstream = const ServerUpstreamConfig(),
    this.filter = const ServerFilterConfig(),
    this.cache = const ServerCacheConfig(),
    this.queryLog = const ServerQueryLogConfig(),
    this.mirrorTemplates = const [],
  });

  final ServerListenConfig listen;
  final ServerUpstreamConfig upstream;
  final ServerFilterConfig filter;
  final ServerCacheConfig cache;
  final ServerQueryLogConfig queryLog;

  /// 服务器模式自己的镜像站模板，供订阅下载加速选择。
  final List<String> mirrorTemplates;

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
    mirrorTemplates: [
      for (final item in (json['mirrorTemplates'] as List?) ?? const [])
        if (item is String && item.trim().isNotEmpty) item,
    ],
  );

  Map<String, Object?> toJson() => {
    'listen': listen.toJson(),
    'upstream': upstream.toJson(),
    'filter': filter.toJson(),
    'cache': cache.toJson(),
    'queryLog': queryLog.toJson(),
    if (mirrorTemplates.isNotEmpty) 'mirrorTemplates': mirrorTemplates,
  };

  ServerConfig copyWith({
    ServerListenConfig? listen,
    ServerUpstreamConfig? upstream,
    ServerFilterConfig? filter,
    ServerCacheConfig? cache,
    ServerQueryLogConfig? queryLog,
    List<String>? mirrorTemplates,
  }) => ServerConfig(
    listen: listen ?? this.listen,
    upstream: upstream ?? this.upstream,
    filter: filter ?? this.filter,
    cache: cache ?? this.cache,
    queryLog: queryLog ?? this.queryLog,
    mirrorTemplates: mirrorTemplates ?? this.mirrorTemplates,
  );
}
