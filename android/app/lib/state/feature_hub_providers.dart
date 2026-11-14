/// Hidden card set and the log long-press hint; keys must match `featureKey` in
/// `lib/data/mock_feature_hub.dart`.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `HiddenFeaturesStore.PREFS_NAME` (global UI container).
const hiddenFeaturesContainer = LegacySettings.uiContainer;

/// `HiddenFeaturesStore.KEY_HIDDEN_FEATURES`.
const hiddenFeaturesKey = 'hidden_features_set';

/// The same key list in source order, pinned against `mock_feature_hub.dart` by the tests.
const hiddenFeatureKeysInFile = <String>[
  'provider_management',
  'bootstrap_settings',
  'resolution_mode',
  'cache_settings',
  'rule_control',
  'blacklist',
  'whitelist',
  'rewrite_list',
  'traffic_stats',
  'app_rules',
  'blocked_apps',
  'excluded_apps',
  'flow_view',
  'network_diagnostics',
  'app_insights',
  'privacy_suite',
  'dns64',
  'ip_quality',
  'automation',
  'automation_profiles',
  'timetable',
  'network_profile',
  'subscriptions',
  'auto_update',
  'mirror_templates',
  'local_api',
  'webhook',
  'lan_rate_limit',
  'custom_resources',
  'https_inspection',
  'outbound_proxy',
  'network_tools',
  'agent_api',
  'appearance',
  'service_display',
  'other_settings',
  'logs',
  'request_logs',
  'data_management',
  'data_cleanup',
  'troubleshooting',
  'app_info',
  'sponsor',
  'sponsor_list',
  'contributors',
];

/// Currently hidden feature keys, persisted. Readers watch the revision, or the hub keeps stale
/// cards.
class HiddenFeatureKeysNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(legacySettingsRevisionProvider);
    final store = ref.watch(legacyPrefsStoreProvider);
    final value = store.read(hiddenFeaturesContainer, hiddenFeaturesKey);
    // The bridge delivers a List, and old installs may hold a JSON string.
    if (value is List) {
      return {
        for (final item in value)
          if (item is String && item.isNotEmpty) item,
      };
    }
    return const {};
  }

  void setVisible(String key, bool visible) {
    final next = {...state};
    if (visible) {
      next.remove(key);
    } else {
      next.add(key);
    }
    _write(next);
  }

  void toggle(String key) => setVisible(key, !state.contains(key));

  void resetAll() => _write(const {});

  void _write(Set<String> next) {
    ref
        .read(legacyPrefsStoreProvider)
        .putStringSet(hiddenFeaturesContainer, hiddenFeaturesKey, next);
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }
}

final hiddenFeatureKeysProvider =
    NotifierProvider<HiddenFeatureKeysNotifier, Set<String>>(
      HiddenFeatureKeysNotifier.new,
    );

/// Visible hub categories for the current mode, localized with the caller's `context.l10n`.
///
/// The resources are a family argument instead of `currentL10n` on purpose: the provider only
/// recomputes when a dependency changes, and a language switch touches none of them, so reading
/// the global would keep the previous language's cards until the app restarts.
final visibleFeatureCategoriesProvider =
    Provider.family<List<MockFeatureCategory>, AppL10n>((ref, l10n) {
      final express = ref.watch(workModeProvider) == AppWorkMode.express;
      final hidden = ref.watch(hiddenFeatureKeysProvider);
      return visibleFeatureCategories(
        express: express,
        hiddenKeys: hidden,
        l10n: l10n,
      );
    });

/// Whether the log card's long-press hint was acknowledged. Session-only, 1.4.3 has no storage key.
class LogLongPressHintNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void acknowledge() => state = false;
}

final logLongPressHintProvider =
    NotifierProvider<LogLongPressHintNotifier, bool>(
      LogLongPressHintNotifier.new,
    );
