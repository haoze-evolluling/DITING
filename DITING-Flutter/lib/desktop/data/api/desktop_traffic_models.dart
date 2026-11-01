/// The recognised LAN clients and the two limits applied to them: `/api/v1/clients` plus the
/// `access` / `rateLimit` blocks of `/api/v1/status`.
///
/// The old desktop console's `ClientsPanel.vue` is the blueprint. A client is identified by address
/// only; the name is either the service's rDNS guess or an alias the user set here.
library;

int _int(Object? value) => switch (value) {
  num() => value.toInt(),
  String() => int.tryParse(value) ?? 0,
  _ => 0,
};

double _double(Object? value) => switch (value) {
  num() => value.toDouble(),
  String() => double.tryParse(value) ?? 0,
  _ => 0,
};

bool _bool(Object? value) => value == true;

List<String> _strings(Object? value) => switch (value) {
  List() => [
    for (final item in value)
      if ('$item'.trim().isNotEmpty) '$item'.trim(),
  ],
  _ => const [],
};

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

/// One recognised client.
class DesktopClient {
  const DesktopClient({
    required this.ip,
    required this.name,
    required this.queryCount,
    required this.lastSeen,
  });

  factory DesktopClient.fromJson(Map<String, Object?> json) => DesktopClient(
    ip: '${json['ip'] ?? ''}',
    name: '${json['name'] ?? ''}',
    queryCount: _int(json['queryCount']),
    lastSeen: _int(json['lastSeen']),
  );

  final String ip;

  /// Empty when neither rDNS nor an alias produced a name.
  final String name;
  final int queryCount;

  /// Unix seconds; zero means the service never recorded activity.
  final int lastSeen;
}

List<DesktopClient> desktopClients(Object? value) => switch (value) {
  List() => [
    for (final item in value)
      if (item is Map)
        DesktopClient.fromJson(item.cast<String, Object?>()),
  ],
  _ => const [],
};

/// The whitelist / blocklist pair. An empty whitelist means "no restriction".
class DesktopAccessControl {
  const DesktopAccessControl({
    this.allowed = const [],
    this.blocked = const [],
  });

  factory DesktopAccessControl.fromJson(Map<String, Object?> json) =>
      DesktopAccessControl(
        allowed: _strings(json['allowedClients']),
        blocked: _strings(json['blockedClients']),
      );

  final List<String> allowed;
  final List<String> blocked;

  bool allows(String ip) => allowed.contains(ip);

  bool blocks(String ip) => blocked.contains(ip);
}

/// The token-bucket limit. The service clamps out-of-range values, so a save re-reads the answer.
class DesktopRateLimit {
  const DesktopRateLimit({
    required this.enabled,
    required this.rate,
    required this.burst,
    required this.ipv4Prefix,
    required this.ipv6Prefix,
    required this.exemptIPs,
  });

  factory DesktopRateLimit.fromJson(Map<String, Object?> json) =>
      DesktopRateLimit(
        enabled: _bool(json['enabled']),
        rate: _double(json['rate']),
        burst: _int(json['burst']),
        ipv4Prefix: _int(json['ipv4Prefix']),
        ipv6Prefix: _int(json['ipv6Prefix']),
        exemptIPs: _strings(json['exemptIPs']),
      );

  final bool enabled;
  final double rate;
  final int burst;
  final int ipv4Prefix;
  final int ipv6Prefix;
  final List<String> exemptIPs;

  /// The service's own defaults, used by the reset button and by an empty answer.
  static const fallback = DesktopRateLimit(
    enabled: false,
    rate: 50,
    burst: 100,
    ipv4Prefix: 32,
    ipv6Prefix: 128,
    exemptIPs: ['127.0.0.1', '::1'],
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'rate': rate,
    'burst': burst,
    'ipv4Prefix': ipv4Prefix,
    'ipv6Prefix': ipv6Prefix,
    'exemptIPs': exemptIPs,
  };
}

/// The two limit blocks read together from `/status`.
class DesktopClientLimits {
  const DesktopClientLimits({required this.access, required this.rateLimit});

  factory DesktopClientLimits.fromJson(Map<String, Object?> json) =>
      DesktopClientLimits(
        access: DesktopAccessControl.fromJson(_map(json['access'])),
        rateLimit: DesktopRateLimit.fromJson(_map(json['rateLimit'])),
      );

  final DesktopAccessControl access;
  final DesktopRateLimit rateLimit;
}
