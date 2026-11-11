/// Backup file: `{format, version, data}`; `data` is keyed by [BackupGroup.key].
library;

import 'package:diting_shared/app/l10n/l10n.dart';

/// Backup groups; declaration order is the export screen order.
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

  /// Key in `data`. Never rename: existing backups depend on it.
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
  /// Top-level `format` value. Changing it invalidates every existing backup.
  static const magic = 'diting-backup';

  /// Version this build writes. 2 dropped the 1.4.3 flat fields (rules, apps, settings at the top
  /// level) that every backup used to carry next to `data`; nothing else changed. Version 1 wrote
  /// the same grouped `data`, so it still restores and only newer files are refused.
  static const version = 2;

  /// Highest version this build parses; newer backups are rejected.
  static const maxReadableVersion = 2;

  static const fileNamePrefix = 'DITING-backup';

  static String stampOf(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}-'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}

/// Backup parse/validation failure; the message is user-visible.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
