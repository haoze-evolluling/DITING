/// User agents and on-demand connection in one notifier: every operation replaces a whole table.
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

  /// Selected user agent; null means no override (subscription or engine default).
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
  /// Writes one table back to prefs; a `state` listener cannot tell which table changed.
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

  void _put(ConfigResources next) => state = next;

  /// Returns false for an empty or duplicate value; the caller shows a message.
  bool addUserAgent(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        state.userAgents.any((item) => item.value == trimmed)) {
      return false;
    }
    final next = state.copyWith(
      userAgents: [
        ...state.userAgents,
        MockUserAgent(value: trimmed),
      ],
    );
    _put(next);
    _store.saveUserAgents(next.userAgents);
    return true;
  }

  bool updateUserAgent(String original, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        state.userAgents.any(
          (item) => item.value == trimmed && item.value != original,
        )) {
      return false;
    }
    // Read the selection before `_put`: afterwards it already holds the new value.
    final selectedWasOriginal = state.selectedUserAgent == original;
    final next = state.copyWith(
      userAgents: [
        for (final item in state.userAgents)
          item.value == original
              ? MockUserAgent(value: trimmed, isDefault: item.isDefault)
              : item,
      ],
      // Follow the rename when the edited entry was selected, or it points at nothing.
      selectedUserAgent: selectedWasOriginal ? trimmed : null,
    );
    _put(next);
    _store.saveUserAgents(next.userAgents);
    if (selectedWasOriginal) _store.saveSelectedUserAgent(trimmed);
    return true;
  }

  /// Built-in agents cannot be removed: the engine falls back and the setting looks unapplied.
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
    _put(next);
    _store.saveUserAgents(next.userAgents);
    // Persist the cleared selection too, or a restart shows "selected" for a missing agent.
    if (selectedWasRemoved) _store.saveSelectedUserAgent(null);
  }

  void selectUserAgent(String? value) {
    _put(
      state.copyWith(
        selectedUserAgent: value,
        clearSelectedUserAgent: value == null,
      ),
    );
    _store.saveSelectedUserAgent(value);
  }

  void setOnDemand(bool value) {
    _put(state.copyWith(onDemand: value));
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
    _put(next);
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
    _put(next);
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
    _put(next);
    _store.saveSsidRules(next.ssidRules);
  }
}

final configResourcesProvider =
    NotifierProvider<ConfigResourcesNotifier, ConfigResources>(
      ConfigResourcesNotifier.new,
    );

/// The `User-Agent` every outbound HTTP client sends. Watching this provider is what makes
/// `/config/user-agents` a real setting instead of a stored string.
final requestUserAgentProvider = Provider<String>(
  (ref) => resolveRequestUserAgent(
    ref.watch(
      configResourcesProvider.select((state) => state.selectedUserAgent),
    ),
  ),
);
