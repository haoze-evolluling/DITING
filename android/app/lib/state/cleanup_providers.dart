library;

import 'dart:async';

import 'package:diting_android/data/cleanup/data_cleanup_service.dart';
import 'package:diting_shared/data/db/app_database.dart';
import 'package:diting_shared/data/db/rule_index_bridge.dart';
import 'package:diting_shared/data/native/platform_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/app_version_provider.dart';
import 'package:diting_android/state/automation_providers.dart';
import 'package:diting_android/state/ca_inspection_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/outbound_proxy_providers.dart';
import 'package:diting_android/state/recognition_providers.dart';
import 'package:diting_android/state/runtime_log_providers.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:diting_android/state/troubleshooting_log_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    openDatabase: AppDatabase.open,
  );
});

class CleanupProgressNotifier extends Notifier<CleanupAction?> {
  @override
  CleanupAction? build() => null;

  void set(CleanupAction? action) => state = action;
}

final cleanupProgressProvider =
    NotifierProvider<CleanupProgressNotifier, CleanupAction?>(
      CleanupProgressNotifier.new,
    );

class CleanupRunner {
  CleanupRunner(this._ref);

  final Ref _ref;

  Future<CleanupResult> run(CleanupAction action) async {
    final progress = _ref.read(cleanupProgressProvider.notifier);
    progress.set(action);
    try {
      final result = await _ref.read(dataCleanupServiceProvider).run(action);
      if (result.removed > 0 || !result.failed) _invalidate(action);
      _refreshIndexes(action);
      return result;
    } finally {
      progress.set(null);
    }
  }

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

  void _invalidate(CleanupAction action) {
    _ref.read(dnsLogRevisionProvider.notifier).bump();
    _ref.read(subscriptionRevisionProvider.notifier).bump();
    _ref.read(legacySettingsRevisionProvider.notifier).bump();
    _ref.read(outboundProxyRevisionProvider.notifier).bump();
    _ref.invalidate(caCertificateStateProvider);
    final all = action == CleanupAction.allData;
    if (all || action == CleanupAction.automationEvents) {
      _ref.read(automationRevisionProvider.notifier).bump();
    }
    if (all || action == CleanupAction.runtimeLogs) {
      _ref.invalidate(runtimeLogStatusProvider);
      _ref.invalidate(troubleshootingLogsProvider);
    }
    if (all || action == CleanupAction.recognitionMembers) {
      _ref.invalidate(recognitionMembersProvider);
      _ref.invalidate(recognitionAvatarProvider);
    }
  }
}

final cleanupRunnerProvider = Provider<CleanupRunner>(CleanupRunner.new);
