/// The LAN web console: `/api/v1/web/status` and the admin credential state it carries.
///
/// The old desktop console's `LanWebCard.vue` is the blueprint. `firewallBackend == "none"` means the
/// host has no firewall manager to configure, so the port is already open and the page hides the
/// allow-rule switch instead of pretending it can toggle something.
library;

bool _bool(Object? value) => value == true;

int _int(Object? value) => switch (value) {
  num() => value.toInt(),
  String() => int.tryParse(value) ?? 0,
  _ => 0,
};

List<String> _strings(Object? value) => switch (value) {
  List() => [for (final item in value) '$item'],
  _ => const [],
};

/// `GET /api/v1/web/status`.
class DesktopWebStatus {
  const DesktopWebStatus({
    required this.enabled,
    required this.port,
    required this.listenAddress,
    required this.lanAddresses,
    required this.webUrls,
    required this.firewallAllowed,
    required this.firewallBackend,
    required this.initialized,
    required this.username,
  });

  factory DesktopWebStatus.fromJson(Map<String, Object?> json) =>
      DesktopWebStatus(
        enabled: _bool(json['enabled']),
        port: _int(json['port']),
        listenAddress: '${json['listenAddress'] ?? ''}',
        lanAddresses: _strings(json['lanAddresses']),
        webUrls: _strings(json['webUrls']),
        firewallAllowed: _bool(json['firewallAllowed']),
        firewallBackend: '${json['firewallBackend'] ?? ''}',
        initialized: _bool(json['initialized']),
        username: '${json['username'] ?? ''}',
      );

  final bool enabled;
  final int port;
  final String listenAddress;
  final List<String> lanAddresses;

  /// Browser URLs on the LAN; empty when no IPv4 interface was found.
  final List<String> webUrls;
  final bool firewallAllowed;

  /// Empty or unknown values are treated as "supported", as the console did.
  final String firewallBackend;
  final bool initialized;

  /// Empty before the first setup.
  final String username;

  bool get firewallSupported => firewallBackend != 'none';
}
