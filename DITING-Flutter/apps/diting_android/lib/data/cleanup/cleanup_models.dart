library;

import 'package:diting_shared/app/l10n/l10n.dart';
enum CleanupAction {
  logs,
  traffic,
  crash,
  dnsCache,
  providerWeights,
  bootstrapWeights,
  domainRules,
  addressRules,
  subscriptions,
  appRules,
  outboundProxy,
  caCertificate,
  downloadCache,
  customBackground,
  settingsGuides,
  allData;

  String title(AppL10n l10n) => switch (this) {
    CleanupAction.logs => l10n.cleanupLogs,
    CleanupAction.traffic => l10n.cleanupTraffic,
    CleanupAction.crash => l10n.cleanupCrash,
    CleanupAction.dnsCache => l10n.cleanupDnsCache,
    CleanupAction.providerWeights => l10n.cleanupProviderWeights,
    CleanupAction.bootstrapWeights => l10n.cleanupBootstrapWeights,
    CleanupAction.domainRules => l10n.cleanupDomainRules,
    CleanupAction.addressRules => l10n.cleanupAddressRules,
    CleanupAction.subscriptions => l10n.cleanupSubscriptions,
    CleanupAction.appRules => l10n.cleanupAppRules,
    CleanupAction.outboundProxy => l10n.cleanupOutboundProxy,
    CleanupAction.caCertificate => l10n.cleanupCaCertificate,
    CleanupAction.downloadCache => l10n.cleanupDownloadCache,
    CleanupAction.customBackground => l10n.cleanupCustomBackground,
    CleanupAction.settingsGuides => l10n.cleanupSettingsGuides,
    CleanupAction.allData => l10n.cleanupAllData,
  };

  /// Whether the process must exit after this action; both also clear `initial_agreement_accepted`.
  bool get exitsApp => this == settingsGuides || this == allData;

  /// Whether the engine must reload afterwards, or it keeps using the stale copy.
  bool get affectsEngine => const {
    domainRules,
    addressRules,
    subscriptions,
    appRules,
    outboundProxy,
  }.contains(this);
}

class CleanupResult {
  const CleanupResult({
    required this.action,
    required this.removed,
    this.detail,
  });

  const CleanupResult.failed(this.action, String this.detail) : removed = 0;

  final CleanupAction action;

  /// Removed rows / files / keys. Zero is a valid result, not a failure.
  final int removed;

  final String? detail;

  bool get failed => detail != null && removed == 0;

  /// User-facing message; with zero rows it says there was nothing to clean.
  String get message {
    if (removed > 0) {
      final suffix = detail == null ? '' : '（$detail）';
      return currentL10n.cleanupDoneItems(action.title(currentL10n), removed, suffix);
    }
    return detail ??
        currentL10n.cleanupDoneEmpty(action.title(currentL10n));
  }
}
