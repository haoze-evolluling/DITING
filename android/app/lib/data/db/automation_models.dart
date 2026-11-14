/// Automation rule / profile / event models (A1 / A3 / A14).
///
/// The condition-action *logic* is evaluated by the Kotlin `AutomationEngine`; this file only types
/// the documents stored in `automation_rule` / `automation_profile` / `automation_event` so the
/// editor, the list and the audit timeline agree on one shape. `spec_json` and `payload_json` are
/// kept as opaque maps here — their schema is validated where they are produced (the editor) and
/// where they are consumed (the engine), never re-invented per screen.
library;

import 'dart:convert';

/// One condition-action rule row.
class AutomationRule {
  const AutomationRule({
    required this.id,
    required this.name,
    this.enabled = true,
    this.priority = 100,
    this.match = 'all',
    this.spec = const {},
    this.lastRunAt = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final bool enabled;
  final int priority;

  /// `all` / `any`: how multiple conditions combine.
  final String match;

  /// `{trigger, conditions, actions}`; see `AutomationSpec` below for the canonical keys.
  final Map<String, Object?> spec;
  final int lastRunAt;
  final int createdAt;
  final int updatedAt;

  String get triggerType =>
      (spec['trigger'] as Map?)?['type'] as String? ?? 'manual';

  List<Map<String, Object?>> get conditions {
    final raw = spec['conditions'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) Map<String, Object?>.from(item),
    ];
  }

  List<Map<String, Object?>> get actions {
    final raw = spec['actions'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) Map<String, Object?>.from(item),
    ];
  }

  static AutomationRule fromRow(Map<String, Object?> row) => AutomationRule(
    id: (row['id'] as String?) ?? '',
    name: (row['name'] as String?) ?? '',
    enabled: ((row['enabled'] as num?)?.toInt() ?? 1) != 0,
    priority: (row['priority'] as num?)?.toInt() ?? 100,
    match: (row['match'] as String?) ?? 'all',
    spec: _decodeMap(row['spec_json']),
    lastRunAt: (row['last_run_at'] as num?)?.toInt() ?? 0,
    createdAt: (row['created_at'] as num?)?.toInt() ?? 0,
    updatedAt: (row['updated_at'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'enabled': enabled ? 1 : 0,
    'priority': priority,
    'match': match,
    'spec_json': jsonEncode(spec),
    'last_run_at': lastRunAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  AutomationRule copyWith({
    String? name,
    bool? enabled,
    int? priority,
    String? match,
    Map<String, Object?>? spec,
    int? lastRunAt,
    int? updatedAt,
  }) => AutomationRule(
    id: id,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    priority: priority ?? this.priority,
    match: match ?? this.match,
    spec: spec ?? this.spec,
    lastRunAt: lastRunAt ?? this.lastRunAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// One configuration profile (A3): a one-tap snapshot of work mode / upstream set / rule-group
/// states / feature toggles.
class AutomationProfile {
  const AutomationProfile({
    required this.id,
    required this.name,
    this.payload = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;

  /// `{workMode, upstreamSet, ruleGroupStates, featureToggles}`.
  final Map<String, Object?> payload;
  final int createdAt;
  final int updatedAt;

  String get workMode => (payload['workMode'] as String?) ?? 'normal';
  String get upstreamSet => (payload['upstreamSet'] as String?) ?? '';

  List<String> get ruleGroupStates {
    final raw = payload['ruleGroupStates'];
    if (raw is! List) return const [];
    return [for (final item in raw) if (item is String) item];
  }

  static AutomationProfile fromRow(Map<String, Object?> row) => AutomationProfile(
    id: (row['id'] as String?) ?? '',
    name: (row['name'] as String?) ?? '',
    payload: _decodeMap(row['payload_json']),
    createdAt: (row['created_at'] as num?)?.toInt() ?? 0,
    updatedAt: (row['updated_at'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'payload_json': jsonEncode(payload),
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

/// One audit row: when a rule fired and what it did.
class AutomationEvent {
  const AutomationEvent({
    this.id = 0,
    required this.ts,
    this.ruleId = '',
    required this.event,
    this.outcome = '',
    this.detail = const {},
  });

  final int id;
  final int ts;
  final String ruleId;
  final String event;
  final String outcome;
  final Map<String, Object?> detail;

  static AutomationEvent fromRow(Map<String, Object?> row) => AutomationEvent(
    id: (row['id'] as num?)?.toInt() ?? 0,
    ts: (row['ts'] as num?)?.toInt() ?? 0,
    ruleId: (row['rule_id'] as String?) ?? '',
    event: (row['event'] as String?) ?? '',
    outcome: (row['outcome'] as String?) ?? '',
    detail: _decodeMap(row['detail_json']),
  );

  Map<String, Object?> toRow() => {
    'ts': ts,
    'rule_id': ruleId,
    'event': event,
    'outcome': outcome,
    'detail_json': jsonEncode(detail),
  };
}

/// The canonical trigger / condition / action tokens shared by the editor and the engine.
abstract final class AutomationSpec {
  static const triggerManual = 'manual';
  static const triggerSchedule = 'schedule';
  static const triggerNetwork = 'network';
  static const triggerState = 'state';

  static const actionPause = 'pause';
  static const actionSwitchProfile = 'switch_profile';
  static const actionSwitchUpstream = 'switch_upstream';
  static const actionToggleRuleGroup = 'toggle_rule_group';
  static const actionBlockServices = 'block_services';

  /// A brand-new empty rule document.
  static Map<String, Object?> blank() => {
    'trigger': {'type': triggerManual},
    'conditions': <Object?>[],
    'actions': [
      {'type': actionPause, 'minutes': 60},
    ],
  };
}

Map<String, Object?> _decodeMap(Object? raw) {
  if (raw is Map) return Map<String, Object?>.from(raw);
  if (raw is String && raw.isNotEmpty) {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
  }
  return const {};
}

/// A collision-resistant id without pulling a uuid package: microseconds plus a per-process counter.
int _sequence = 0;
String newAutomationId(String prefix) {
  _sequence += 1;
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_sequence';
}
