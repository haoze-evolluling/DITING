/// The blocking schedule: the global time plan (`/filter/schedule`) and the per-service weekly plans
/// carried inside `/filter/services`.
///
/// One row is a named window: a start and an end `HH:MM` (end earlier than start crosses midnight)
/// and the weekdays it applies to. An empty weekday list means every day, as the service documents.
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

  /// A row with no times is not a window; the console drops those before saving.
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

/// `GET /api/v1/filter/schedule`.
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

  /// Whether blocking is inside a window right now (always true when no plan is on).
  final bool active;

  /// The window that matched, or empty.
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

/// One service's plan state, as `/filter/services` reports it under `scheduleStates`.
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

  /// False means the plan exists but this instant is outside its window.
  final bool active;
}
