/// Fixtures for the local authoritative zones, and the service-side rebuild the fake performs after
/// a save so the card can be asserted against what the service would report.
library;

const String desktopZoneLanContent =
    '\$ORIGIN lan.\n'
    '@   IN SOA ns.lan. admin.lan. (1 7200 3600 1209600 300)\n'
    'www IN A 192.168.1.10\n';

const String desktopZoneIntraContent =
    '\$ORIGIN intra.example.com.\n'
    '@   IN SOA ns.intra.example.com. admin.intra.example.com. (1 7200 3600 1209600 300)\n'
    'nas IN A 10.0.0.20\n';

/// A `GET /api/v1/dns/zone/config` payload: two zones, one enabled, one disabled.
Map<String, Object?> zonePayload({
  bool enabled = true,
  int ttl = 300,
  List<Map<String, Object?>>? zones,
  List<Map<String, Object?>>? states,
  int? recordCount,
  int maxZones = 32,
  int maxRecords = 10000,
}) {
  final entries =
      zones ??
      const [
        {
          'id': 'zone-lan',
          'origin': 'lan.',
          'content': desktopZoneLanContent,
          'enabled': true,
        },
        {
          'id': 'zone-intra',
          'origin': 'intra.example.com.',
          'content': desktopZoneIntraContent,
          'enabled': false,
        },
      ];
  final built = states ?? zoneStates(entries);
  return {
    'enabled': enabled,
    'ttl': ttl,
    'zones': entries,
    'states': built,
    'recordCount':
        recordCount ??
        built.fold<int>(
          0,
          (sum, state) => sum + ((state['records'] as num?)?.toInt() ?? 0),
        ),
    'maxZones': maxZones,
    'maxRecords': maxRecords,
  };
}

/// The per-zone build result the fake reports: an enabled zone with an apex loads two names, a
/// disabled one is reported as not loaded with the reason the real engine gives.
List<Map<String, Object?>> zoneStates(List<Map<String, Object?>> zones) => [
  for (final zone in zones)
    {
      'id': zone['id'],
      'origin': zone['origin'],
      'records': zone['enabled'] == true ? 2 : 0,
      'loaded': zone['enabled'] == true,
      if (zone['enabled'] != true) 'error': 'zone disabled',
    },
];

/// What `POST /api/v1/dns/zone/config` leaves behind: the body merged over the config, then the
/// zones rebuilt the way the engine would.
Map<String, Object?> zoneConfigAfter(
  Map<String, Object?> config,
  Map<String, Object?> body,
) {
  final merged = {...config, ...body};
  final zones = [
    for (final item in merged['zones'] as List? ?? const [])
      (item as Map).cast<String, Object?>(),
  ];
  final states = [
    for (final zone in zones)
      () {
        final enabled = zone['enabled'] == true;
        final origin = '${zone['origin'] ?? ''}'.trim();
        final content = '${zone['content'] ?? ''}'.trim();
        final loaded = enabled && origin.isNotEmpty && content.isNotEmpty;
        return {
          'id': zone['id'],
          'origin': zone['origin'],
          'records': loaded ? 2 : 0,
          'loaded': loaded,
          if (!loaded)
            'error': !enabled
                ? 'zone disabled'
                : origin.isEmpty
                ? 'missing origin'
                : 'empty zone',
        };
      }(),
  ];
  return {
    ...merged,
    'zones': zones,
    'states': states,
    'recordCount': states.fold<int>(
      0,
      (sum, state) => sum + ((state['records'] as num?)?.toInt() ?? 0),
    ),
  };
}

/// A `POST /api/v1/dns/zone/test` answer. `success` is the engine's own verdict, not the request's.
Map<String, Object?> zoneTestPayload({
  bool success = true,
  List<String> records = const ['www.lan. 300 IN A 192.168.1.10'],
  String error = '',
}) => {'success': success, 'records': records, 'error': error};
