/// The privacy and protocol-hardening config, read from `/api/v1/status`.
///
/// The console reads the same fields from `status.dns`, `status.ecs`, `status.rebind` and
/// `status.hosts`; each has its own write endpoint that the service merges, so a switch never
/// rewrites an unrelated field.
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

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

/// The EDNS padding sizes the console offers; a value outside the list is shown as-is.
const List<int> desktopEdnsPaddingSizes = [0, 128, 256, 468];

/// The two minimal-answer shapes for ANY queries.
const List<String> desktopAnyModes = ['notimp', 'rfc8482'];

class DesktopPrivacyConfig {
  const DesktopPrivacyConfig({
    required this.enableEde,
    required this.blockPrivatePtr,
    required this.blockUnqualified,
    required this.blockEch,
    required this.blockIpv6,
    required this.blockAny,
    required this.blockAnyMode,
    required this.ednsPadding,
    required this.ecsEnabled,
    required this.ecsStrip,
    required this.ecsCustomSubnet,
    required this.rebindEnabled,
    required this.rebindAllowedDomains,
    required this.hostsEnabled,
    required this.hostsUseSystem,
    required this.hostsCustomFiles,
    required this.hostsTtl,
  });

  factory DesktopPrivacyConfig.fromJson(Map<String, Object?> json) {
    final dns = _map(json['dns']);
    final ecs = _map(json['ecs']);
    final rebind = _map(json['rebind']);
    final hosts = _map(json['hosts']);
    return DesktopPrivacyConfig(
      enableEde: dns['enableEDE'] != false,
      blockPrivatePtr: dns['blockPrivatePTR'] != false,
      blockUnqualified: _bool(dns['blockUnqualified']),
      blockEch: _bool(dns['blockECH']),
      blockIpv6: _bool(dns['blockIPv6']),
      blockAny: _bool(dns['blockANY']),
      blockAnyMode: '${dns['blockANYMode'] ?? ''}',
      ednsPadding: _int(dns['ednsPadding']),
      ecsEnabled: ecs['enabled'] != false,
      ecsStrip: ecs['stripECS'] != false,
      ecsCustomSubnet: '${ecs['customSubnet'] ?? ''}',
      rebindEnabled: rebind['enabled'] != false,
      rebindAllowedDomains: _strings(rebind['allowedDomains']),
      hostsEnabled: hosts['enabled'] != false,
      hostsUseSystem: hosts['useSystemHost'] != false,
      hostsCustomFiles: _strings(hosts['customFiles']),
      hostsTtl: _int(hosts['ttl']),
    );
  }

  final bool enableEde;
  final bool blockPrivatePtr;
  final bool blockUnqualified;
  final bool blockEch;
  final bool blockIpv6;
  final bool blockAny;

  /// `notimp` (the service's default) or `rfc8482`.
  final String blockAnyMode;
  final int ednsPadding;

  final bool ecsEnabled;
  final bool ecsStrip;
  final String ecsCustomSubnet;

  final bool rebindEnabled;
  final List<String> rebindAllowedDomains;

  final bool hostsEnabled;
  final bool hostsUseSystem;
  final List<String> hostsCustomFiles;
  final int hostsTtl;

  String get effectiveAnyMode =>
      blockAnyMode == 'rfc8482' ? 'rfc8482' : 'notimp';

  DesktopPrivacyConfig copyWith({
    bool? enableEde,
    bool? blockPrivatePtr,
    bool? blockUnqualified,
    bool? blockEch,
    bool? blockIpv6,
    bool? blockAny,
    String? blockAnyMode,
    int? ednsPadding,
    bool? ecsEnabled,
    bool? ecsStrip,
    String? ecsCustomSubnet,
    bool? rebindEnabled,
    List<String>? rebindAllowedDomains,
    bool? hostsEnabled,
    bool? hostsUseSystem,
    List<String>? hostsCustomFiles,
    int? hostsTtl,
  }) => DesktopPrivacyConfig(
    enableEde: enableEde ?? this.enableEde,
    blockPrivatePtr: blockPrivatePtr ?? this.blockPrivatePtr,
    blockUnqualified: blockUnqualified ?? this.blockUnqualified,
    blockEch: blockEch ?? this.blockEch,
    blockIpv6: blockIpv6 ?? this.blockIpv6,
    blockAny: blockAny ?? this.blockAny,
    blockAnyMode: blockAnyMode ?? this.blockAnyMode,
    ednsPadding: ednsPadding ?? this.ednsPadding,
    ecsEnabled: ecsEnabled ?? this.ecsEnabled,
    ecsStrip: ecsStrip ?? this.ecsStrip,
    ecsCustomSubnet: ecsCustomSubnet ?? this.ecsCustomSubnet,
    rebindEnabled: rebindEnabled ?? this.rebindEnabled,
    rebindAllowedDomains:
        rebindAllowedDomains ?? this.rebindAllowedDomains,
    hostsEnabled: hostsEnabled ?? this.hostsEnabled,
    hostsUseSystem: hostsUseSystem ?? this.hostsUseSystem,
    hostsCustomFiles: hostsCustomFiles ?? this.hostsCustomFiles,
    hostsTtl: hostsTtl ?? this.hostsTtl,
  );

  /// The protocol-privacy subset, which `/dns/privacy/configure` merges.
  Map<String, Object?> privacyJson() => {
    'enableEDE': enableEde,
    'blockPrivatePTR': blockPrivatePtr,
    'blockIPv6': blockIpv6,
    'blockECH': blockEch,
    'blockANY': blockAny,
    'blockANYMode': effectiveAnyMode,
    'ednsPadding': ednsPadding,
  };
}
