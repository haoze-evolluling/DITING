library;

import 'package:diting_android/data/cleanup/cleanup_models.dart';
import 'package:diting_android/app/l10n/l10n.dart';

enum CleanupCategory {
  runtime,
  weights,
  rules,
  storage,
  guides;

  String get id => name;

  String title(AppL10n l10n) => switch (this) {
    CleanupCategory.runtime => l10n.cleanupGroupRuntime,
    CleanupCategory.weights => l10n.cleanupGroupWeights,
    CleanupCategory.rules => l10n.cleanupGroupRules,
    CleanupCategory.storage => l10n.cleanupGroupStorage,
    CleanupCategory.guides => l10n.cleanupGroupGuides,
  };

  List<CleanupAction> get actions => switch (this) {
    CleanupCategory.runtime => [
      CleanupAction.logs,
      CleanupAction.runtimeLogs,
      CleanupAction.traffic,
      CleanupAction.crash,
      CleanupAction.dnsCache,
      CleanupAction.automationEvents,
    ],
    CleanupCategory.weights => [
      CleanupAction.providerWeights,
      CleanupAction.bootstrapWeights,
    ],
    CleanupCategory.rules => [
      CleanupAction.domainRules,
      CleanupAction.addressRules,
      CleanupAction.subscriptions,
      CleanupAction.appRules,
      CleanupAction.ruleVersions,
      CleanupAction.mirrorTemplates,
    ],
    CleanupCategory.storage => [
      CleanupAction.outboundProxy,
      CleanupAction.caCertificate,
      CleanupAction.downloadCache,
      CleanupAction.customBackground,
      CleanupAction.recognitionMembers,
    ],
    CleanupCategory.guides => [CleanupAction.settingsGuides],
  };

  static CleanupCategory? fromId(String? id) {
    for (final category in values) {
      if (category.id == id) return category;
    }
    return null;
  }
}
