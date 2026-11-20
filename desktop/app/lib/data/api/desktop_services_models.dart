library;

import 'package:diting_desktop/data/api/desktop_schedule_models.dart';

int _int(Object? value) => switch (value) {
  num() => value.toInt(),
  String() => int.tryParse(value) ?? 0,
  _ => 0,
};

List<String> _strings(Object? value) => switch (value) {
  List() => [for (final item in value) '$item'],
  _ => const [],
};

class DesktopBlockedService {
  const DesktopBlockedService({
    required this.id,
    required this.name,
    required this.group,
    required this.rules,
    required this.ruleCount,
    required this.source,
  });

  factory DesktopBlockedService.fromJson(Map<String, Object?> json) =>
      DesktopBlockedService(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        group: '${json['group'] ?? ''}',
        rules: _strings(json['rules']),
        ruleCount: _int(json['ruleCount']),
        source: '${json['source'] ?? ''}',
      );

  final String id;
  final String name;
  final String group;

  final List<String> rules;
  final int ruleCount;
  final String source;
}

class DesktopServiceGroup {
  const DesktopServiceGroup({
    required this.id,
    required this.name,
    required this.count,
  });

  factory DesktopServiceGroup.fromJson(Map<String, Object?> json) =>
      DesktopServiceGroup(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        count: _int(json['count']),
      );

  final String id;
  final String name;
  final int count;
}

class DesktopBlockedServices {
  const DesktopBlockedServices({
    required this.services,
    required this.groups,
    required this.blockedIds,
    required this.blockedGroups,
    required this.activeRules,
    required this.schedules,
    required this.scheduleStates,
  });

  factory DesktopBlockedServices.fromJson(Map<String, Object?> json) =>
      DesktopBlockedServices(
        services: [
          for (final item in json['services'] as List? ?? const [])
            if (item is Map)
              DesktopBlockedService.fromJson(item.cast<String, Object?>()),
        ],
        groups: [
          for (final item in json['groups'] as List? ?? const [])
            if (item is Map)
              DesktopServiceGroup.fromJson(item.cast<String, Object?>()),
        ],
        blockedIds: _strings(json['blockedIds']).toSet(),
        blockedGroups: _strings(json['blockedGroups']).toSet(),
        activeRules: _int(json['activeRules']),
        schedules: switch (json['schedules']) {
          Map() => {
            for (final entry in (json['schedules'] as Map).entries)
              '${entry.key}': desktopSchedules(entry.value),
          },
          _ => const {},
        },
        scheduleStates: _scheduleStates(json['scheduleStates']),
      );

  static const empty = DesktopBlockedServices(
    services: [],
    groups: [],
    blockedIds: {},
    blockedGroups: {},
    activeRules: 0,
    schedules: {},
    scheduleStates: {},
  );

  final List<DesktopBlockedService> services;
  final List<DesktopServiceGroup> groups;
  final Set<String> blockedIds;
  final Set<String> blockedGroups;
  final int activeRules;

  final Map<String, List<DesktopSchedule>> schedules;
  final Map<String, DesktopServiceScheduleState> scheduleStates;

  bool blockedByGroup(DesktopBlockedService service) =>
      !blockedIds.contains(service.id) &&
      blockedGroups.contains(service.group);

  bool isBlocked(DesktopBlockedService service) =>
      blockedIds.contains(service.id) || blockedByGroup(service);

  int get blockedCount => services.where(isBlocked).length;

  DesktopServiceScheduleState? stateOf(String serviceId) =>
      scheduleStates[serviceId];

  List<DesktopSchedule> schedulesOf(String serviceId) =>
      schedules[serviceId] ?? const [];

  String groupName(String groupId) {
    for (final group in groups) {
      if (group.id == groupId) return group.name;
    }
    return groupId;
  }
}

Map<String, DesktopServiceScheduleState> _scheduleStates(Object? value) {
  final states = <String, DesktopServiceScheduleState>{};
  for (final item in value as List? ?? const []) {
    if (item is! Map) continue;
    final state = DesktopServiceScheduleState.fromJson(
      item.cast<String, Object?>(),
    );
    states[state.serviceId] = state;
  }
  return states;
}
