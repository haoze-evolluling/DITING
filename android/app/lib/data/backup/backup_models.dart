library;

import 'package:diting_android/app/l10n/l10n.dart';

enum BackupGroup {
  providers('providers'),
  bootstrap('bootstrap'),
  cache('cache'),
  outbound('outbound'),
  subscriptions('subscriptions'),
  domainRules('domainRules'),
  rewriteDomain('rewriteDomain'),
  rewriteCname('rewriteCname'),
  addressRules('addressRules'),
  excluded('excluded'),
  blocked('blocked'),
  allowlist('allowlist'),
  httpInspection('httpInspection'),
  appearance('appearance'),
  system('system');

  const BackupGroup(this.key);

  final String key;

  String title(AppL10n l10n) => switch (this) {
    BackupGroup.providers => l10n.backupGroupProviders,
    BackupGroup.bootstrap => l10n.backupGroupBootstrap,
    BackupGroup.cache => l10n.backupGroupCache,
    BackupGroup.outbound => l10n.backupGroupOutbound,
    BackupGroup.subscriptions => l10n.backupGroupSubscriptions,
    BackupGroup.domainRules => l10n.backupGroupDomainRules,
    BackupGroup.rewriteDomain => l10n.backupGroupRewriteDomain,
    BackupGroup.rewriteCname => l10n.backupGroupRewriteCname,
    BackupGroup.addressRules => l10n.backupGroupAddressRules,
    BackupGroup.excluded => l10n.backupGroupExcluded,
    BackupGroup.blocked => l10n.backupGroupBlocked,
    BackupGroup.allowlist => l10n.backupGroupAllowlist,
    BackupGroup.httpInspection => l10n.backupGroupHttpInspection,
    BackupGroup.appearance => l10n.backupGroupAppearance,
    BackupGroup.system => l10n.backupGroupSystem,
  };

  String description(AppL10n l10n) => switch (this) {
    BackupGroup.providers => l10n.backupGroupProvidersDesc,
    BackupGroup.bootstrap => l10n.backupGroupBootstrapDesc,
    BackupGroup.cache => l10n.backupGroupCacheDesc,
    BackupGroup.outbound => l10n.backupGroupOutboundDesc,
    BackupGroup.subscriptions => l10n.backupGroupSubscriptionsDesc,
    BackupGroup.domainRules => l10n.backupGroupDomainRulesDesc,
    BackupGroup.rewriteDomain => l10n.backupGroupRewriteDomainDesc,
    BackupGroup.rewriteCname => l10n.backupGroupRewriteCnameDesc,
    BackupGroup.addressRules => l10n.backupGroupAddressRulesDesc,
    BackupGroup.excluded => l10n.backupGroupExcludedDesc,
    BackupGroup.blocked => l10n.backupGroupBlockedDesc,
    BackupGroup.allowlist => l10n.backupGroupAllowlistDesc,
    BackupGroup.httpInspection => l10n.backupGroupHttpInspectionDesc,
    BackupGroup.appearance => l10n.backupGroupAppearanceDesc,
    BackupGroup.system => l10n.backupGroupSystemDesc,
  };

  static BackupGroup? fromKey(String? key) {
    for (final group in values) {
      if (group.key == key) return group;
    }
    return null;
  }
}

abstract final class BackupFormat {
  static const magic = 'diting-backup';

  static const version = 3;

  static const maxReadableVersion = 3;

  static const fileNamePrefix = 'DITING-backup';

  static String stampOf(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}-'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}
