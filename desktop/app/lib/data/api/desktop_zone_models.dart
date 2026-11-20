library;

int _int(Object? value) => switch (value) {
  num() => value.toInt(),
  String() => int.tryParse(value) ?? 0,
  _ => 0,
};

bool _bool(Object? value) => value == true;

String _string(Object? value) => value == null ? '' : '$value';

List<String> _strings(Object? value) => switch (value) {
  List() => [for (final item in value) '$item'],
  _ => const [],
};

const int desktopZoneDefaultTtl = 300;

class DesktopZoneEntry {
  const DesktopZoneEntry({
    required this.id,
    required this.origin,
    required this.content,
    required this.enabled,
  });

  factory DesktopZoneEntry.fromJson(Map<String, Object?> json) =>
      DesktopZoneEntry(
        id: _string(json['id']),
        origin: _string(json['origin']),
        content: _string(json['content']),
        enabled: _bool(json['enabled']),
      );

  final String id;
  final String origin;
  final String content;
  final bool enabled;

  DesktopZoneEntry copyWith({String? origin, String? content, bool? enabled}) =>
      DesktopZoneEntry(
        id: id,
        origin: origin ?? this.origin,
        content: content ?? this.content,
        enabled: enabled ?? this.enabled,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'origin': origin,
    'content': content,
    'enabled': enabled,
  };
}

class DesktopZoneState {
  const DesktopZoneState({
    required this.id,
    required this.origin,
    required this.records,
    required this.loaded,
    required this.error,
  });

  factory DesktopZoneState.fromJson(Map<String, Object?> json) =>
      DesktopZoneState(
        id: _string(json['id']),
        origin: _string(json['origin']),
        records: _int(json['records']),
        loaded: _bool(json['loaded']),
        error: _string(json['error']),
      );

  final String id;
  final String origin;
  final int records;
  final bool loaded;
  final String error;
}

class DesktopZoneConfig {
  const DesktopZoneConfig({
    required this.enabled,
    required this.ttl,
    this.zones = const [],
    this.states = const [],
    this.recordCount = 0,
    this.maxZones = 32,
    this.maxRecords = 10000,
  });

  factory DesktopZoneConfig.fromJson(Map<String, Object?> json) =>
      DesktopZoneConfig(
        enabled: _bool(json['enabled']),
        ttl: _int(json['ttl']),
        zones: [
          for (final item in json['zones'] as List? ?? const [])
            if (item is Map)
              DesktopZoneEntry.fromJson(item.cast<String, Object?>()),
        ],
        states: [
          for (final item in json['states'] as List? ?? const [])
            if (item is Map)
              DesktopZoneState.fromJson(item.cast<String, Object?>()),
        ],
        recordCount: _int(json['recordCount']),
        maxZones: _int(json['maxZones']) > 0 ? _int(json['maxZones']) : 32,
        maxRecords: _int(json['maxRecords']) > 0
            ? _int(json['maxRecords'])
            : 10000,
      );

  final bool enabled;
  final int ttl;
  final List<DesktopZoneEntry> zones;
  final List<DesktopZoneState> states;
  final int recordCount;
  final int maxZones;
  final int maxRecords;

  int get effectiveTtl => ttl > 0 ? ttl : desktopZoneDefaultTtl;

  DesktopZoneState? stateOf(String id) {
    for (final state in states) {
      if (state.id == id) return state;
    }
    return null;
  }

  DesktopZoneConfig copyWith({
    bool? enabled,
    int? ttl,
    List<DesktopZoneEntry>? zones,
  }) => DesktopZoneConfig(
    enabled: enabled ?? this.enabled,
    ttl: ttl ?? this.ttl,
    zones: zones ?? this.zones,
    states: states,
    recordCount: recordCount,
    maxZones: maxZones,
    maxRecords: maxRecords,
  );
}

class DesktopZoneTest {
  const DesktopZoneTest({
    required this.success,
    this.records = const [],
    this.error = '',
  });

  factory DesktopZoneTest.fromJson(Map<String, Object?> json) =>
      DesktopZoneTest(
        success: _bool(json['success']),
        records: _strings(json['records']),
        error: _string(json['error']),
      );

  final bool success;
  final List<String> records;
  final String error;
}
