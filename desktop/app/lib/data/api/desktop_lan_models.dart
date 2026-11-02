/// The LAN DNS service: `/api/v1/dns/lan` and the two writes that change it.
///
/// The old desktop console's `LanDnsCard.vue` is the blueprint. `firewallBackend == "none"` means the
/// host has no firewall manager to configure, so port 53 is already open and the page explains that
/// instead of offering a switch it cannot honour.
library;

bool _bool(Object? value) => value == true;

List<String> _strings(Object? value) => switch (value) {
  List() => [for (final item in value) '$item'],
  _ => const [],
};

/// `GET /api/v1/dns/lan`.
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

  /// Whether the service listens on `0.0.0.0`/`[::]` rather than loopback only.
  final bool allowLan;

  /// The addresses the service is bound to right now.
  final List<String> listenAddresses;

  /// The host's own LAN IPv4/IPv6 addresses, i.e. what a router or phone should point at.
  final List<String> lanAddresses;
  final bool firewallAllowed;

  /// Empty or unknown values are treated as "supported", as the console did.
  final String firewallBackend;

  bool get firewallSupported => firewallBackend != 'none';
}
