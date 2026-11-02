/// The host's network adapters and which of them the service is currently taking over.
///
/// The old desktop console's `network/AdaptersPanel.vue` is the blueprint. `/adapters` reports the
/// adapter's own properties (gateway, IP mode, the DNS it had before) and `/status` reports the
/// takeover set as ids *or* names, so the page has to accept either.
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

/// `GET /api/v1/adapters` — one entry per adapter the host considers usable.
class DesktopAdapter {
  const DesktopAdapter({
    required this.id,
    required this.name,
    required this.description,
    required this.index,
    required this.status,
    required this.gateway,
    required this.ipv4Dhcp,
    required this.ipv6Dhcp,
    required this.ipv4Dns,
    required this.ipv6Dns,
    required this.isPhysical,
    required this.hasResidualLoopback,
  });

  factory DesktopAdapter.fromJson(Map<String, Object?> json) => DesktopAdapter(
    id: '${json['id'] ?? ''}',
    name: '${json['name'] ?? ''}',
    description: '${json['description'] ?? ''}',
    index: _int(json['index']),
    status: '${json['status'] ?? ''}',
    gateway: '${json['gateway'] ?? ''}',
    ipv4Dhcp: _bool(json['ipv4DHCP']),
    ipv6Dhcp: _bool(json['ipv6DHCP']),
    ipv4Dns: _strings(json['ipv4DNS']),
    ipv6Dns: _strings(json['ipv6DNS']),
    isPhysical: _bool(json['isPhysical']),
    hasResidualLoopback: _bool(json['hasResidualLoopback']),
  );

  /// Windows GUID or the Linux interface name; also the takeover key.
  final String id;
  final String name;
  final String description;
  final int index;

  /// `Up` when the adapter carries traffic; every other value is shown as-is.
  final String status;
  final String gateway;
  final bool ipv4Dhcp;
  final bool ipv6Dhcp;

  /// The DNS the adapter had before any takeover; empty when it was obtained automatically.
  final List<String> ipv4Dns;
  final List<String> ipv6Dns;
  final bool isPhysical;
  final bool hasResidualLoopback;

  bool get isUp => status.toLowerCase() == 'up';

  /// Both stacks, so a v6-only adapter still shows what it had.
  List<String> get dns => [...ipv4Dns, ...ipv6Dns];
}
