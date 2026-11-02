part of 'backup_importer.dart';

/// App-list groups (excluded / blocked / allowlist / HTTPS inspection); all four merge with local
/// data and an import never removes entries.
extension _BackupImportLists on BackupImporter {
  BackupGroupOutcome _importExcluded(Object? value, BackupImportTarget target) {
    final incoming = _stringSet(value);
    if (incoming.isEmpty) {
      return const BackupGroupOutcome(group: BackupGroup.excluded, skipped: 1);
    }
    final settings = target.settings;
    final merged = {...settings.excludedPackages, ...incoming};
    final added = merged.length - settings.excludedPackages.length;
    settings.setExcludedPackages(merged);
    return BackupGroupOutcome(
      group: BackupGroup.excluded,
      added: added,
      skipped: incoming.length - added,
    );
  }

  BackupGroupOutcome _importBlocked(Object? value, BackupImportTarget target) {
    if (value is! Map) {
      throw BackupFormatException(currentL10n.backupErrBlockedNotObject);
    }
    final incoming = _stringSet(value['packages']);
    final settings = target.settings;
    final merged = {...settings.blockedAppPackages, ...incoming};
    final added = merged.length - settings.blockedAppPackages.length;
    settings.setBlockedApps(
      packages: merged,
      // OR the switch with the local value so an imported enable is not lost.
      enabled: settings.blockedAppsEnabled || value['enabled'] == true,
    );
    return BackupGroupOutcome(
      group: BackupGroup.blocked,
      added: added,
      skipped: incoming.length - added,
    );
  }

  BackupGroupOutcome _importAllowlist(
    Object? value,
    BackupImportTarget target,
  ) {
    if (value is! Map) {
      throw BackupFormatException(currentL10n.backupErrAppRulesNotObject);
    }
    final rules = value['rules'];
    final settings = target.settings;
    final merged = {
      for (final entry in settings.appAllowlistRules.entries)
        entry.key: {...entry.value},
    };
    var added = 0;
    if (rules is Map) {
      for (final entry in rules.entries) {
        final package = '${entry.key}';
        if (package.trim().isEmpty) continue;
        final domains = _stringSet(entry.value);
        if (domains.isEmpty) continue;
        final existing = merged[package] ?? <String>{};
        final before = existing.length;
        merged[package] = {...existing, ...domains};
        added += merged[package]!.length - before;
      }
    }
    settings.setAppAllowlistRules(merged);
    settings.setAppAllowlistEnabled(
      settings.appAllowlistEnabled || value['enabled'] == true,
    );
    return BackupGroupOutcome(
      group: BackupGroup.allowlist,
      added: added,
      skipped: added == 0 ? 1 : 0,
    );
  }

  BackupGroupOutcome _importHttpInspection(
    Object? value,
    BackupImportTarget target,
  ) {
    if (value is! Map) {
      throw BackupFormatException(currentL10n.backupErrInspectionNotObject);
    }
    final incoming = _stringSet(value['packages']);
    final settings = target.settings;
    final merged = {...settings.httpInspectionPackages, ...incoming};
    final added = merged.length - settings.httpInspectionPackages.length;
    settings.setHttpInspectionApps(
      packages: merged,
      // Inspection is never enabled by an import: `https_inspection_ready` depends on a locally
      // installed CA, so enabling it would break HTTPS.
      enabled: settings.httpInspectionEnabled,
    );
    final http3 = value['http3Enabled'];
    if (http3 is bool) {
      settings.setHttpInspectionToggles(
        http3: http3,
        encryptedDns: settings.encryptedDnsBlockingEnabled,
        addressRules: settings.addressRulesEnabled,
      );
    }
    return BackupGroupOutcome(
      group: BackupGroup.httpInspection,
      added: added,
      skipped: incoming.length - added,
    );
  }
}
