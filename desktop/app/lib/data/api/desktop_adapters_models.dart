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

  final String id;
  final String name;
  final String description;
  final int index;

  final String status;
  final String gateway;
  final bool ipv4Dhcp;
  final bool ipv6Dhcp;

  final List<String> ipv4Dns;
  final List<String> ipv6Dns;
  final bool isPhysical;
  final bool hasResidualLoopback;

  bool get isUp => status.toLowerCase() == 'up';

  List<String> get dns => [...ipv4Dns, ...ipv6Dns];
}
