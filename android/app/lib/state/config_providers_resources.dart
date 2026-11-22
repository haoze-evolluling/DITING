library;

import 'package:diting_android/data/http/request_user_agent.dart';
import 'package:diting_android/data/mock_config_resources.dart';
import 'package:diting_android/data/prefs/config_resource_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConfigResources {
  const ConfigResources({
    required this.userAgents,
    required this.selectedUserAgent,
    required this.ssidRules,
    required this.onDemand,
  });

  final List<MockUserAgent> userAgents;

  final String? selectedUserAgent;
  final List<MockSsidRule> ssidRules;
  final bool onDemand;

  ConfigResources copyWith({
    List<MockUserAgent>? userAgents,
    String? selectedUserAgent,
    bool clearSelectedUserAgent = false,
    List<MockSsidRule>? ssidRules,
    bool? onDemand,
  }) => ConfigResources(
    userAgents: userAgents ?? this.userAgents,
    selectedUserAgent: clearSelectedUserAgent
        ? null
        : (selectedUserAgent ?? this.selectedUserAgent),
    ssidRules: ssidRules ?? this.ssidRules,
    onDemand: onDemand ?? this.onDemand,
  );
}

class ConfigResourcesNotifier extends Notifier<ConfigResources> {
  ConfigResourceStore get _store =>
      ConfigResourceStore(ref.read(legacyPrefsStoreProvider));

  @override
  ConfigResources build() {
    final snapshot = ConfigResourceStore(ref.watch(legacyPrefsStoreProvider))
        .load();
    return ConfigResources(
      userAgents: snapshot.userAgents,
      selectedUserAgent: snapshot.selectedUserAgent,
      ssidRules: snapshot.ssidRules,
      onDemand: snapshot.onDemand,
    );
  }

  bool addUserAgent(String value, {String? name}) {
    final trimmed = value.trim();
    final label = (name ?? '').trim();
    if (trimmed.isEmpty ||
        state.userAgents.any((item) => item.value == trimmed) ||
        (label.isNotEmpty &&
            state.userAgents.any((item) => item.name == label))) {
      return false;
    }
    final next = state.copyWith(
      userAgents: [
        ...state.userAgents,
        MockUserAgent(value: trimmed, name: label),
      ],
    );
    state = next;
    _store.saveUserAgents(next.userAgents);
    return true;
  }

  bool updateUserAgent(String original, String value, {String? name}) {
    final trimmed = value.trim();
    final label = name?.trim();
    if (trimmed.isEmpty ||
        state.userAgents.any(
          (item) => item.value == trimmed && item.value != original,
        ) ||
        (label != null &&
            label.isNotEmpty &&
            state.userAgents.any(
              (item) => item.name == label && item.value != original,
            ))) {
      return false;
    }
    final selectedWasOriginal = state.selectedUserAgent == original;
    final next = state.copyWith(
      userAgents: [
        for (final item in state.userAgents)
          item.value == original
              ? MockUserAgent(
                  value: trimmed,
                  name: label ?? item.name,
                  isDefault: item.isDefault,
                )
              : item,
      ],
      selectedUserAgent: selectedWasOriginal ? trimmed : null,
    );
    state = next;
    _store.saveUserAgents(next.userAgents);
    if (selectedWasOriginal) _store.saveSelectedUserAgent(trimmed);
    return true;
  }

  void removeUserAgent(String value) {
    if (state.userAgents.any((item) => item.value == value && item.isDefault)) {
      return;
    }
    final selectedWasRemoved = state.selectedUserAgent == value;
    final next = state.copyWith(
      userAgents: [
        for (final item in state.userAgents)
          if (item.value != value) item,
      ],
      clearSelectedUserAgent: selectedWasRemoved,
    );
    state = next;
    _store.saveUserAgents(next.userAgents);
    if (selectedWasRemoved) _store.saveSelectedUserAgent(null);
  }

  void selectUserAgent(String? value) {
    state = state.copyWith(
      selectedUserAgent: value,
      clearSelectedUserAgent: value == null,
    );
    _store.saveSelectedUserAgent(value);
  }

  void setOnDemand(bool value) {
    state = state.copyWith(onDemand: value);
    _store.saveOnDemand(value);
  }

  bool putSsid(String? original, MockSsidRule rule) {
    final trimmed = rule.ssid.trim();
    if (trimmed.isEmpty ||
        state.ssidRules.any(
          (item) => item.ssid == trimmed && item.ssid != original,
        )) {
      return false;
    }
    final normalized = MockSsidRule(
      ssid: trimmed,
      cellular: rule.cellular,
      wifi: rule.wifi,
      delayMs: rule.delayMs,
    );
    final next = state.copyWith(
      ssidRules: original == null
          ? [...state.ssidRules, normalized]
          : [
              for (final item in state.ssidRules)
                item.ssid == original ? normalized : item,
            ],
    );
    state = next;
    _store.saveSsidRules(next.ssidRules);
    return true;
  }

  void removeSsid(String ssid) {
    final next = state.copyWith(
      ssidRules: [
        for (final item in state.ssidRules)
          if (item.ssid != ssid) item,
      ],
    );
    state = next;
    _store.saveSsidRules(next.ssidRules);
  }

  void toggleSsid(String ssid, {bool? cellular, bool? wifi}) {
    final next = state.copyWith(
      ssidRules: [
        for (final item in state.ssidRules)
          item.ssid == ssid
              ? item.copyWith(cellular: cellular, wifi: wifi)
              : item,
      ],
    );
    state = next;
    _store.saveSsidRules(next.ssidRules);
  }
}

final configResourcesProvider =
    NotifierProvider<ConfigResourcesNotifier, ConfigResources>(
      ConfigResourcesNotifier.new,
    );

final requestUserAgentProvider = Provider<String>(
  (ref) => resolveRequestUserAgent(
    ref.watch(
      configResourcesProvider.select((state) => state.selectedUserAgent),
    ),
  ),
);
