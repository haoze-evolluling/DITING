part of 'server_models.dart';

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
    this.prefetchThreshold = 3,
    this.prefetchBeforeExpiryMs = 3000,
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
  final int prefetchThreshold;
  final int prefetchBeforeExpiryMs;

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
        prefetchThreshold:
            (json['prefetchThreshold'] as num?)?.toInt() ?? 3,
        prefetchBeforeExpiryMs:
            (json['prefetchBeforeExpiryMs'] as num?)?.toInt() ?? 3000,
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
    'prefetchThreshold': prefetchThreshold,
    'prefetchBeforeExpiryMs': prefetchBeforeExpiryMs,
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
    int? prefetchThreshold,
    int? prefetchBeforeExpiryMs,
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
    prefetchThreshold: prefetchThreshold ?? this.prefetchThreshold,
    prefetchBeforeExpiryMs: prefetchBeforeExpiryMs ?? this.prefetchBeforeExpiryMs,
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

