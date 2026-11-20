library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const hiddenFeaturesContainer = LegacySettings.uiContainer;

const hiddenFeaturesKey = 'hidden_features_set';

const hiddenFeatureKeysInFile = <String>[
  'provider_management',
  'resolution_mode',
  'cache_settings',
  'service_display',
  'rule_control',
  'subscriptions',
  'app_rules',
  'privacy_suite',
  'flow_view',
  'network_tools',
  'connection_rate_limit',
  'traffic_stats',
  'network_diagnostics',
  'https_inspection',
  'outbound_proxy',
  'agent_api',
  'data_management',
  'data_cleanup',
  'troubleshooting',
  'log_retention',
  'logs',
  'foreground_behavior',
  'appearance',
  'other_settings',
  'app_info',
];

class HiddenFeatureKeysNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(legacySettingsRevisionProvider);
    final store = ref.watch(legacyPrefsStoreProvider);
    final value = store.read(hiddenFeaturesContainer, hiddenFeaturesKey);
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

class LogLongPressHintNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void acknowledge() => state = false;
}

final logLongPressHintProvider =
    NotifierProvider<LogLongPressHintNotifier, bool>(
      LogLongPressHintNotifier.new,
    );
