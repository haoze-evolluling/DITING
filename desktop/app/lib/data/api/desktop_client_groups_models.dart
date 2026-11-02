/// Client groups and the options a group can bind: `/api/v1/clients/groups`.
///
/// The old desktop console's `ClientGroupsCard.vue` is the blueprint. A group is matched by longest
/// prefix over its members; an empty rule-list selection inherits every subscription and an empty
/// upstream selection inherits the main chain, which is why both are stored as plain lists.
library;

import 'package:diting_desktop/data/api/desktop_schedule_models.dart';

bool _bool(Object? value) => value == true;

List<String> _strings(Object? value) => switch (value) {
  List() => [
    for (final item in value)
      if ('$item'.trim().isNotEmpty) '$item'.trim(),
  ],
  _ => const [],
};

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

/// One group. The page edits a draft of this shape and saves the whole list at once.
class DesktopClientGroup {
  const DesktopClientGroup({
    this.id = '',
    this.name = '',
    this.enabled = true,
    this.clients = const [],
    this.ruleListIds = const [],
    this.blockMode = '',
    this.upstreamIds = const [],
    this.scheduleEnabled = false,
    this.schedules = const [],
    this.allowlistOnly = false,
  });

  factory DesktopClientGroup.fromJson(Map<String, Object?> json) =>
      DesktopClientGroup(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        enabled: _bool(json['enabled']),
        clients: _strings(json['clients']),
        ruleListIds: _strings(json['ruleListIds']),
        blockMode: '${json['blockMode'] ?? ''}',
        upstreamIds: _strings(json['upstreamIds']),
        scheduleEnabled: _bool(json['scheduleEnabled']),
        schedules: desktopSchedules(json['schedules']),
        allowlistOnly: _bool(json['allowlistOnly']),
      );

  final String id;
  final String name;
  final bool enabled;

  /// IPs or CIDR ranges.
  final List<String> clients;

  /// Empty inherits every subscription.
  final List<String> ruleListIds;

  /// Empty inherits the global blocking mode.
  final String blockMode;

  /// Empty inherits the main upstream chain.
  final List<String> upstreamIds;

  final bool scheduleEnabled;
  final List<DesktopSchedule> schedules;
  final bool allowlistOnly;

  DesktopClientGroup copyWith({
    String? id,
    String? name,
    bool? enabled,
    List<String>? clients,
    List<String>? ruleListIds,
    String? blockMode,
    List<String>? upstreamIds,
    bool? scheduleEnabled,
    List<DesktopSchedule>? schedules,
    bool? allowlistOnly,
  }) => DesktopClientGroup(
    id: id ?? this.id,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    clients: clients ?? this.clients,
    ruleListIds: ruleListIds ?? this.ruleListIds,
    blockMode: blockMode ?? this.blockMode,
    upstreamIds: upstreamIds ?? this.upstreamIds,
    scheduleEnabled: scheduleEnabled ?? this.scheduleEnabled,
    schedules: schedules ?? this.schedules,
    allowlistOnly: allowlistOnly ?? this.allowlistOnly,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'enabled': enabled,
    'clients': clients,
    if (ruleListIds.isNotEmpty) 'ruleListIds': ruleListIds,
    if (blockMode.isNotEmpty) 'blockMode': blockMode,
    if (upstreamIds.isNotEmpty) 'upstreamIds': upstreamIds,
    if (scheduleEnabled) 'scheduleEnabled': true,
    if (scheduleEnabled) 'schedules': [for (final row in schedules) row.toJson()],
    if (allowlistOnly) 'allowlistOnly': true,
  };
}

/// A subscription a group can bind.
class DesktopGroupRuleList {
  const DesktopGroupRuleList({
    required this.id,
    required this.name,
    required this.enabled,
  });

  factory DesktopGroupRuleList.fromJson(Map<String, Object?> json) =>
      DesktopGroupRuleList(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        enabled: _bool(json['enabled']),
      );

  final String id;
  final String name;
  final bool enabled;

  String get label => name.isEmpty ? id : name;
}

/// An upstream node a group can bind.
class DesktopGroupUpstream {
  const DesktopGroupUpstream({
    required this.id,
    required this.protocol,
    required this.server,
  });

  factory DesktopGroupUpstream.fromJson(Map<String, Object?> json) =>
      DesktopGroupUpstream(
        id: '${json['id'] ?? ''}',
        protocol: '${json['protocol'] ?? ''}',
        server: '${json['server'] ?? ''}',
      );

  final String id;
  final String protocol;
  final String server;
}

/// `GET /api/v1/clients/groups`.
class DesktopClientGroups {
  const DesktopClientGroups({
    required this.enabled,
    required this.groups,
    required this.ruleLists,
    required this.upstreams,
  });

  factory DesktopClientGroups.fromJson(Map<String, Object?> json) =>
      DesktopClientGroups(
        enabled: _bool(json['enabled']),
        groups: switch (json['groups']) {
          List() => [
            for (final item in json['groups'] as List)
              if (item is Map)
                DesktopClientGroup.fromJson(_map(item)),
          ],
          _ => const [],
        },
        ruleLists: switch (json['ruleLists']) {
          List() => [
            for (final item in json['ruleLists'] as List)
              if (item is Map)
                DesktopGroupRuleList.fromJson(_map(item)),
          ],
          _ => const [],
        },
        upstreams: switch (json['upstreams']) {
          List() => [
            for (final item in json['upstreams'] as List)
              if (item is Map)
                DesktopGroupUpstream.fromJson(_map(item)),
          ],
          _ => const [],
        },
      );

  final bool enabled;
  final List<DesktopClientGroup> groups;
  final List<DesktopGroupRuleList> ruleLists;
  final List<DesktopGroupUpstream> upstreams;

  int get enabledCount => groups.where((group) => group.enabled).length;
}
