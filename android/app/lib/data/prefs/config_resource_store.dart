/// User agents and on-demand SSID rules as whole JSON blobs, in a container of their own.
library;

import 'dart:convert';

import 'package:diting_android/data/mock_config_resources.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:flutter/foundation.dart';

class ConfigResourceStore {
  const ConfigResourceStore(this._store);

  /// Deliberately not one of the legacy container names.
  static const container = 'diting_config_resources';

  static const _userAgentsKey = 'user_agents_json';
  static const _selectedUaKey = 'selected_user_agent';
  static const _ssidRulesKey = 'ssid_rules_json';
  static const _onDemandKey = 'on_demand_enabled';
  static const _lastSsidKey = 'on_demand_last_ssid';

  final LegacyPrefsStore _store;

  /// Each group falls back to its defaults independently, so one corrupt blob resets nothing else.
  ConfigResourceSnapshot load() {
    final stored = _decodeList(_userAgentsKey, _userAgentFromMap);
    final userAgents = _reconcileUserAgents(stored);
    final ssidRules = _decodeList(_ssidRulesKey, _ssidFromMap);
    final rawSelected = _store.read(container, _selectedUaKey);
    final selectedValue = rawSelected is String && rawSelected.isNotEmpty
        ? rawSelected
        : null;
    return ConfigResourceSnapshot(
      userAgents: userAgents,
      // A stale selection (a retired preset, say) points at nothing, so it reads as no override.
      selectedUserAgent: userAgents.any((agent) => agent.value == selectedValue)
          ? selectedValue
          : null,
      ssidRules: ssidRules ?? mockSsidRules,
      onDemand: _store.read(container, _onDemandKey) == true,
    );
  }

  /// Keeps persisted custom entries, drops retired built-ins and adds newly shipped ones.
  /// Without this, an upgrade would never surface new presets once the list reached disk.
  List<MockUserAgent> _reconcileUserAgents(List<MockUserAgent>? stored) {
    if (stored == null) return mockUserAgents;
    final builtinValues = <String>{
      for (final agent in mockUserAgents)
        if (agent.isDefault) agent.value,
    };
    final kept = <MockUserAgent>[
      for (final agent in stored)
        if (!agent.isDefault || builtinValues.contains(agent.value)) agent,
    ];
    final present = <String>{for (final agent in kept) agent.value};
    for (final agent in mockUserAgents) {
      if (agent.isDefault && !present.contains(agent.value)) {
        kept.add(agent);
      }
    }
    return kept;
  }

  void saveUserAgents(List<MockUserAgent> agents) => _store.putString(
    container,
    _userAgentsKey,
    jsonEncode([
      for (final agent in agents)
        {
          'value': agent.value,
          'name': agent.name,
          'isDefault': agent.isDefault,
        },
    ]),
  );

  /// An empty string is written to tell "no override" from unset.
  void saveSelectedUserAgent(String? value) =>
      _store.putString(container, _selectedUaKey, value ?? '');

  void saveSsidRules(List<MockSsidRule> rules) => _store.putString(
    container,
    _ssidRulesKey,
    jsonEncode([
      for (final rule in rules)
        {
          'ssid': rule.ssid,
          'cellular': rule.cellular,
          'wifi': rule.wifi,
          'delayMs': rule.delayMs,
        },
    ]),
  );

  void saveOnDemand(bool value) =>
      _store.putBool(container, _onDemandKey, value);

  /// The network the whitelist was last applied to, so re-evaluating the same network never
  /// overrides a manual start/stop. `''` (not on Wi-Fi) is a real value; null means never
  /// evaluated.
  String? loadLastEvaluatedSsid() {
    final raw = _store.read(container, _lastSsidKey);
    return raw is String ? raw : null;
  }

  void saveLastEvaluatedSsid(String ssid) =>
      _store.putString(container, _lastSsidKey, ssid);

  /// A missing key returns null so defaults are used; an empty array is valid and stays.
  List<T>? _decodeList<T>(
    String key,
    T? Function(Map<String, Object?>) decode,
  ) {
    final raw = _store.read(container, key);
    if (raw is! String) return null;
    if (raw.trim().isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      debugPrint('config resources: $key 不是合法 JSON，回落到初始值');
      return null;
    }
    if (decoded is! List) {
      debugPrint('config resources: $key 不是数组，回落到初始值');
      return null;
    }
    final result = <T>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final value = decode(Map<String, Object?>.from(item));
      // A bad entry drops only itself.
      if (value != null) result.add(value);
    }
    return result;
  }

  MockUserAgent? _userAgentFromMap(Map<String, Object?> map) {
    final value = map['value'];
    if (value is! String || value.trim().isEmpty) return null;
    final name = map['name'];
    final label = name is String ? name.trim() : '';
    // Rows saved before names existed get a short inferred label, never the raw UA on the card.
    return MockUserAgent(
      value: value,
      name: label.isNotEmpty ? label : _inferName(value),
      isDefault: map['isDefault'] == true,
    );
  }

  /// A short label for a legacy row that shipped without a name. Best-effort for
  /// the common UA shapes; anything unrecognised is truncated.
  String _inferName(String value) {
    if (value.startsWith('curl/')) return 'curl';
    if (value.contains('Edg/')) return 'Edge';
    if (value.contains('Firefox/')) return 'Firefox';
    if (value.contains('Chrome/')) {
      return value.contains('Mobile') || value.contains('Android')
          ? 'Chrome / Android'
          : 'Chrome / Windows';
    }
    if (value.contains('Safari/')) {
      return value.contains('iPhone') || value.contains('Mobile')
          ? 'Safari / iPhone'
          : 'Safari / macOS';
    }
    return value.length <= 32 ? value : '${value.substring(0, 32)}…';
  }

  MockSsidRule? _ssidFromMap(Map<String, Object?> map) {
    final ssid = map['ssid'];
    if (ssid is! String || ssid.trim().isEmpty) return null;
    final delay = map['delayMs'];
    return MockSsidRule(
      ssid: ssid,
      cellular: map['cellular'] == true,
      wifi: map['wifi'] != false,
      delayMs: delay is int ? delay : 0,
    );
  }
}

class ConfigResourceSnapshot {
  const ConfigResourceSnapshot({
    required this.userAgents,
    required this.selectedUserAgent,
    required this.ssidRules,
    required this.onDemand,
  });

  final List<MockUserAgent> userAgents;
  final String? selectedUserAgent;
  final List<MockSsidRule> ssidRules;
  final bool onDemand;
}
