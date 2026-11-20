library;

const List<String> desktopWeekdays = [
  'mon',
  'tue',
  'wed',
  'thu',
  'fri',
  'sat',
  'sun',
];

bool _bool(Object? value) => value == true;

List<String> _weekdays(Object? value) => switch (value) {
  List() => [
    for (final day in value)
      if (desktopWeekdays.contains('$day')) '$day',
  ],
  _ => const [],
};

class DesktopSchedule {
  const DesktopSchedule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.weekdays,
    required this.start,
    required this.end,
  });

  factory DesktopSchedule.fromJson(Map<String, Object?> json) =>
      DesktopSchedule(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        enabled: _bool(json['enabled']),
        weekdays: _weekdays(json['weekdays']),
        start: '${json['start'] ?? ''}',
        end: '${json['end'] ?? ''}',
      );

  final String id;
  final String name;
  final bool enabled;
  final List<String> weekdays;
  final String start;
  final String end;

  bool get isComplete => start.isNotEmpty && end.isNotEmpty;

  DesktopSchedule copyWith({
    String? id,
    String? name,
    bool? enabled,
    List<String>? weekdays,
    String? start,
    String? end,
  }) => DesktopSchedule(
    id: id ?? this.id,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    weekdays: weekdays ?? this.weekdays,
    start: start ?? this.start,
    end: end ?? this.end,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'enabled': enabled,
    'weekdays': weekdays,
    'start': start,
    'end': end,
  };
}

class DesktopScheduleConfig {
  const DesktopScheduleConfig({
    required this.enabled,
    required this.schedules,
    required this.active,
    required this.activeId,
  });

  factory DesktopScheduleConfig.fromJson(Map<String, Object?> json) =>
      DesktopScheduleConfig(
        enabled: _bool(json['enabled']),
        schedules: desktopSchedules(json['schedules']),
        active: json['active'] != false,
        activeId: '${json['activeId'] ?? ''}',
      );

  static const empty = DesktopScheduleConfig(
    enabled: false,
    schedules: [],
    active: true,
    activeId: '',
  );

  final bool enabled;
  final List<DesktopSchedule> schedules;

  final bool active;

  final String activeId;

  int get enabledCount => schedules.where((row) => row.enabled).length;

  DesktopScheduleConfig copyWith({
    bool? enabled,
    List<DesktopSchedule>? schedules,
  }) => DesktopScheduleConfig(
    enabled: enabled ?? this.enabled,
    schedules: schedules ?? this.schedules,
    active: active,
    activeId: activeId,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'schedules': [for (final row in schedules) row.toJson()],
  };
}

List<DesktopSchedule> desktopSchedules(Object? value) => [
  for (final item in value as List? ?? const [])
    if (item is Map) DesktopSchedule.fromJson(item.cast<String, Object?>()),
];

class DesktopServiceScheduleState {
  const DesktopServiceScheduleState({
    required this.serviceId,
    required this.hasSchedule,
    required this.active,
  });

  factory DesktopServiceScheduleState.fromJson(Map<String, Object?> json) =>
      DesktopServiceScheduleState(
        serviceId: '${json['serviceId'] ?? ''}',
        hasSchedule: _bool(json['hasSchedule']),
        active: _bool(json['active']),
      );

  final String serviceId;
  final bool hasSchedule;

  final bool active;
}
