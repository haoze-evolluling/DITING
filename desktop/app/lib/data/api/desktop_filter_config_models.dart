library;

int _int(Object? value) => switch (value) {
  num() => value.toInt(),
  String() => int.tryParse(value) ?? 0,
  _ => 0,
};

bool _bool(Object? value) => value == true;

List<String> _strings(Object? value) => switch (value) {
  List() => [for (final item in value) '$item'],
  _ => const [],
};

const List<String> desktopBlockModes = ['null_ip', 'nxdomain', 'refused'];

class DesktopFilterConfig {
  const DesktopFilterConfig({
    required this.enabled,
    required this.blockMode,
    required this.blockingIPv4,
    required this.blockingIPv6,
    required this.updateIntervalHours,
    required this.filterResponse,
    required this.allowlistOnly,
    required this.bogusNxDomain,
    required this.bogusNxDomainNetworks,
  });

  factory DesktopFilterConfig.fromJson(Map<String, Object?> json) =>
      DesktopFilterConfig(
        enabled: _bool(json['enabled']),
        blockMode: '${json['blockMode'] ?? ''}',
        blockingIPv4: '${json['blockingIPv4'] ?? ''}',
        blockingIPv6: '${json['blockingIPv6'] ?? ''}',
        updateIntervalHours: _int(json['updateIntervalHours']),
        filterResponse: _bool(json['filterResponse']),
        allowlistOnly: _bool(json['allowlistOnly']),
        bogusNxDomain: _bool(json['bogusNxDomain']),
        bogusNxDomainNetworks: _strings(json['bogusNxDomainNetworks']),
      );

  final bool enabled;

  final String blockMode;

  final String blockingIPv4;
  final String blockingIPv6;
  final int updateIntervalHours;
  final bool filterResponse;
  final bool allowlistOnly;
  final bool bogusNxDomain;
  final List<String> bogusNxDomainNetworks;

  String get effectiveBlockMode =>
      blockMode.isEmpty ? desktopBlockModes.first : blockMode;

  int get effectiveIntervalHours =>
      updateIntervalHours > 0 ? updateIntervalHours : 24;

  DesktopFilterConfig copyWith({
    bool? enabled,
    String? blockMode,
    String? blockingIPv4,
    String? blockingIPv6,
    int? updateIntervalHours,
    bool? filterResponse,
    bool? allowlistOnly,
    bool? bogusNxDomain,
    List<String>? bogusNxDomainNetworks,
  }) => DesktopFilterConfig(
    enabled: enabled ?? this.enabled,
    blockMode: blockMode ?? this.blockMode,
    blockingIPv4: blockingIPv4 ?? this.blockingIPv4,
    blockingIPv6: blockingIPv6 ?? this.blockingIPv6,
    updateIntervalHours: updateIntervalHours ?? this.updateIntervalHours,
    filterResponse: filterResponse ?? this.filterResponse,
    allowlistOnly: allowlistOnly ?? this.allowlistOnly,
    bogusNxDomain: bogusNxDomain ?? this.bogusNxDomain,
    bogusNxDomainNetworks:
        bogusNxDomainNetworks ?? this.bogusNxDomainNetworks,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'blockMode': blockMode,
    'blockingIPv4': blockingIPv4,
    'blockingIPv6': blockingIPv6,
    'updateIntervalHours': updateIntervalHours,
    'filterResponse': filterResponse,
    'allowlistOnly': allowlistOnly,
    'bogusNxDomain': bogusNxDomain,
    'bogusNxDomainNetworks': bogusNxDomainNetworks,
  };
}

class DesktopFilterPause {
  const DesktopFilterPause({
    required this.paused,
    required this.remaining,
    required this.blockingEnabled,
  });

  factory DesktopFilterPause.fromJson(Map<String, Object?> json) =>
      DesktopFilterPause(
        paused: _bool(json['paused']),
        remaining: Duration(seconds: _int(json['remainingSeconds'])),
        blockingEnabled: json['blockingEnabled'] != false,
      );

  static const idle = DesktopFilterPause(
    paused: false,
    remaining: Duration.zero,
    blockingEnabled: true,
  );

  final bool paused;
  final Duration remaining;

  final bool blockingEnabled;
}
