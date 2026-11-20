library;

bool _bool(Object? value) => value == true;

List<String> _strings(Object? value) => switch (value) {
  List() => [for (final item in value) '$item'],
  _ => const [],
};

class DesktopLanStatus {
  const DesktopLanStatus({
    required this.allowLan,
    required this.listenAddresses,
    required this.lanAddresses,
    required this.firewallAllowed,
    required this.firewallBackend,
  });

  factory DesktopLanStatus.fromJson(Map<String, Object?> json) =>
      DesktopLanStatus(
        allowLan: _bool(json['allowLAN']),
        listenAddresses: _strings(json['listenAddresses']),
        lanAddresses: _strings(json['lanAddresses']),
        firewallAllowed: _bool(json['firewallAllowed']),
        firewallBackend: '${json['firewallBackend'] ?? ''}',
      );

  final bool allowLan;

  final List<String> listenAddresses;

  final List<String> lanAddresses;
  final bool firewallAllowed;

  final String firewallBackend;

  bool get firewallSupported => firewallBackend != 'none';
}
