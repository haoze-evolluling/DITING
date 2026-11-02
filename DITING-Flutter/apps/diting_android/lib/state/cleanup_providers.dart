/// Data cleanup; `dataCleanupServiceProvider` wires prefs, channels and the DB opener, degrading to
/// delete 0.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:async';

import 'package:diting_android/data/cleanup/data_cleanup_service.dart';
import 'package:diting_shared/data/db/legacy_database.dart';
import 'package:diting_shared/data/db/rule_index_bridge.dart';
import 'package:diting_shared/data/native/platform_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/app_version_provider.dart';
import 'package:diting_android/state/ca_inspection_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/outbound_proxy_providers.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Native channel; the default already folds every failure into "unavailable".
final platformBridgeProvider = Provider<PlatformBridge>(
  (ref) => PlatformBridge(),
);

final dataCleanupServiceProvider = Provider<DataCleanupService>((ref) {
  return DataCleanupService(
    prefs: ref.watch(legacyPrefsStoreProvider),
    platform: ref.watch(platformBridgeProvider),
    outboundProxy: ref.watch(outboundProxyStoreProvider),
    caCertificate: ref.watch(caCertificateServiceProvider),
    appVersionCode: ref.watch(appVersionProvider).code,
    openDatabase: LegacyDatabase.open,
  );
});

/// Action currently running; the page disables the list and shows progress.
class CleanupProgressNotifier extends Notifier<CleanupAction?> {
  @override
  CleanupAction? build() => null;

  void set(CleanupAction? action) => state = action;
}

final cleanupProgressProvider =
    NotifierProvider<CleanupProgressNotifier, CleanupAction?>(
      CleanupProgressNotifier.new,
    );

/// Runs one action and makes every data page re-query; without the bump pages keep showing deleted
/// rows.
class CleanupRunner {
  CleanupRunner(this._ref);

  final Ref _ref;

  Future<CleanupResult> run(CleanupAction action) async {
    final progress = _ref.read(cleanupProgressProvider.notifier);
    progress.set(action);
    try {
      final result = await _ref.read(dataCleanupServiceProvider).run(action);
      if (result.removed > 0 || !result.failed) _invalidate();
      _refreshIndexes(action);
      return result;
    } finally {
      progress.set(null);
    }
  }

  /// Rule-table cleanups rewrite every rule database at once, so all datasets' tries go stale
  /// together. Recompiling here keeps the next service start on the mmap fast path.
  void _refreshIndexes(CleanupAction action) {
    const ruleActions = {
      CleanupAction.domainRules,
      CleanupAction.addressRules,
      CleanupAction.subscriptions,
      CleanupAction.allData,
    };
    if (!ruleActions.contains(action)) {
      return;
    }
    for (final dataset in RuleIndexDataset.values) {
      unawaited(refreshRuleIndexes(dataset));
    }
  }

  void _invalidate() {
    // Logs, traffic, cache, race and bootstrap tables share this revision.
    _ref.read(dnsLogRevisionProvider.notifier).bump();
    // Subscriptions and mirror templates have their own counters.
    _ref.read(subscriptionRevisionProvider.notifier).bump();
    // Prefs domain: app lists, weights, onboarding flags, wallpaper.
    _ref.read(legacySettingsRevisionProvider.notifier).bump();
    // Outbound proxy is read through a native channel and has its own revision.
    _ref.read(outboundProxyRevisionProvider.notifier).bump();
    // Re-inspect the CA: clearing it changes `https_inspection_ready`.
    _ref.invalidate(caCertificateStateProvider);
  }
}

final cleanupRunnerProvider = Provider<CleanupRunner>(CleanupRunner.new);

/// Group titles, matching 1.4.3 `DataCleanupScreen`.
Map<String, List<CleanupAction>> cleanupGroups(AppL10n l10n) => {
  l10n.cleanupGroupRuntime: [
    CleanupAction.logs,
    CleanupAction.traffic,
    CleanupAction.crash,
    CleanupAction.dnsCache,
  ],
  l10n.cleanupGroupWeights: [
    CleanupAction.providerWeights,
    CleanupAction.bootstrapWeights,
  ],
  l10n.cleanupGroupRules: [
    CleanupAction.domainRules,
    CleanupAction.addressRules,
    CleanupAction.subscriptions,
    CleanupAction.appRules,
  ],
  l10n.cleanupGroupStorage: [
    CleanupAction.outboundProxy,
    CleanupAction.caCertificate,
    CleanupAction.downloadCache,
    CleanupAction.customBackground,
  ],
  l10n.cleanupGroupGuides: [CleanupAction.settingsGuides, CleanupAction.allData],
};
