library;

import 'package:diting_android/data/cleanup/cleanup_plan.dart';
import 'package:diting_android/app/l10n/l10n.dart';

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
  runtimeLogs,
  automationEvents,
  ruleVersions,
  mirrorTemplates,
  recognitionMembers,
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
    CleanupAction.runtimeLogs => l10n.cleanupRuntimeLogs,
    CleanupAction.automationEvents => l10n.cleanupAutomationEvents,
    CleanupAction.ruleVersions => l10n.cleanupRuleVersions,
    CleanupAction.mirrorTemplates => l10n.cleanupMirrorTemplates,
    CleanupAction.recognitionMembers => l10n.cleanupRecognitionMembers,
    CleanupAction.settingsGuides => l10n.cleanupSettingsGuides,
    CleanupAction.allData => l10n.cleanupAllData,
  };

  String description(AppL10n l10n) => switch (this) {
    CleanupAction.logs => l10n.cleanupDescLogs,
    CleanupAction.traffic => l10n.cleanupDescTraffic,
    CleanupAction.crash => l10n.cleanupDescCrash,
    CleanupAction.dnsCache => l10n.cleanupDescDnsCache,
    CleanupAction.providerWeights => l10n.cleanupDescProviderWeights,
    CleanupAction.bootstrapWeights => l10n.cleanupDescBootstrapWeights,
    CleanupAction.domainRules => l10n.cleanupDescDomainRules,
    CleanupAction.addressRules => l10n.cleanupDescAddressRules,
    CleanupAction.subscriptions => l10n.cleanupDescSubscriptions,
    CleanupAction.appRules => l10n.cleanupDescAppRules,
    CleanupAction.outboundProxy => l10n.cleanupDescOutboundProxy,
    CleanupAction.caCertificate => l10n.cleanupDescCaCertificate,
    CleanupAction.downloadCache => l10n.cleanupDescDownloadCache,
    CleanupAction.customBackground => l10n.cleanupDescCustomBackground,
    CleanupAction.runtimeLogs => l10n.cleanupDescRuntimeLogs,
    CleanupAction.automationEvents => l10n.cleanupDescAutomationEvents,
    CleanupAction.ruleVersions => l10n.cleanupDescRuleVersions,
    CleanupAction.mirrorTemplates => l10n.cleanupDescMirrorTemplates,
    CleanupAction.recognitionMembers => l10n.cleanupDescRecognitionMembers,
    CleanupAction.settingsGuides => l10n.cleanupDescSettingsGuides,
    CleanupAction.allData => l10n.cleanupDescAllData,
  };

  String confirmText(AppL10n l10n) => switch (this) {
    CleanupAction.logs => l10n.cleanupConfirmLogs,
    CleanupAction.traffic => l10n.cleanupConfirmTraffic,
    CleanupAction.crash => l10n.cleanupConfirmCrash,
    CleanupAction.dnsCache => l10n.cleanupConfirmDnsCache,
    CleanupAction.providerWeights => l10n.cleanupConfirmProviderWeights,
    CleanupAction.bootstrapWeights => l10n.cleanupConfirmBootstrapWeights,
    CleanupAction.domainRules => l10n.cleanupConfirmDomainRules,
    CleanupAction.addressRules => l10n.cleanupConfirmAddressRules,
    CleanupAction.subscriptions => l10n.cleanupConfirmSubscriptions,
    CleanupAction.appRules => l10n.cleanupConfirmAppRules,
    CleanupAction.outboundProxy => l10n.cleanupConfirmOutboundProxy,
    CleanupAction.caCertificate => l10n.cleanupConfirmCaCertificate,
    CleanupAction.downloadCache => l10n.cleanupConfirmDownloadCache,
    CleanupAction.customBackground => l10n.cleanupConfirmCustomBackground,
    CleanupAction.runtimeLogs => l10n.cleanupConfirmRuntimeLogs,
    CleanupAction.automationEvents => l10n.cleanupConfirmAutomationEvents,
    CleanupAction.ruleVersions => l10n.cleanupConfirmRuleVersions,
    CleanupAction.mirrorTemplates => l10n.cleanupConfirmMirrorTemplates,
    CleanupAction.recognitionMembers => l10n.cleanupConfirmRecognitionMembers,
    CleanupAction.settingsGuides => l10n.cleanupConfirmSettingsGuides,
    CleanupAction.allData => l10n.cleanupConfirmAllData,
  };

  bool get exitsApp => CleanupPlan.instance.exitsApp(name);

  bool get affectsEngine => CleanupPlan.instance.affectsEngine(name);
}

class CleanupResult {
  const CleanupResult({
    required this.action,
    required this.removed,
    this.detail,
  });

  const CleanupResult.failed(this.action, String this.detail) : removed = 0;

  final CleanupAction action;

  final int removed;

  final String? detail;

  bool get failed => detail != null && removed == 0;

  String get message {
    if (removed > 0) {
      final suffix = detail == null ? '' : '（$detail）';
      return currentL10n.cleanupDoneItems(
        action.title(currentL10n),
        removed,
        suffix,
      );
    }
    return detail ?? currentL10n.cleanupDoneEmpty(action.title(currentL10n));
  }
}
