library;

import 'package:diting/app/l10n/l10n.dart';
import 'dart:async';

import 'package:diting/data/backup/backup_exporter.dart';
import 'package:diting/data/backup/backup_importer.dart';
import 'package:diting/data/backup/backup_models.dart';
import 'package:diting/data/db/rule_dataset_providers.dart';
import 'package:diting/data/db/rule_repository.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/data/vpn/dns_config_builder.dart';
import 'package:diting/state/cleanup_providers.dart';
import 'package:diting/state/log_providers.dart';
import 'package:diting/state/subscription_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BackupStats {
  const BackupStats({
    required this.providers,
    required this.subscriptions,
    required this.customRules,
    required this.listedApps,
  });

  const BackupStats.empty()
    : providers = 0,
      subscriptions = 0,
      customRules = 0,
      listedApps = 0;

  final int providers;
  final int subscriptions;
  final int customRules;
  final int listedApps;
}

/// Real stats: providers from prefs, subscriptions and rules from their tables, apps from three
/// lists.
final backupStatsProvider = FutureProvider<BackupStats>((ref) async {
  ref.watch(legacySettingsRevisionProvider);
  ref.watch(subscriptionRevisionProvider);
  ref.watch(dnsLogRevisionProvider);
  final settings = ref.watch(legacySettingsProvider);
  // Rules, subscriptions and their settings all live in the active data set's database.
  final db = await ref.watch(subscriptionDatabaseProvider.future);

  var subscriptions = 0;
  var customRules = 0;
  if (db != null) {
    try {
      final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM subscription');
      subscriptions = (rows.first['n'] as num?)?.toInt() ?? 0;
    } on Exception {
      subscriptions = 0;
    }
    // Counted in SQLite: the overview needs a number, and loading the three tables to count them
    // exhausted the heap on subscription-sized databases.
    try {
      customRules = await RuleRepository(db).countUser();
    } on Exception {
      // A missing table counts as 0: this tile is an overview, not an error.
      customRules = 0;
    }
  }

  final listedApps = {
    ...settings.excludedPackages,
    ...settings.blockedAppPackages,
    ...settings.httpInspectionPackages,
    ...settings.appAllowlistRules.keys,
  }.length;

  return BackupStats(
    providers: _providerCount(settings.userProvidersJson),
    subscriptions: subscriptions,
    customRules: customRules,
    listedApps: listedApps,
  );
});

int _providerCount(String? raw) => parseUserProviders(raw).length;

final backupExporterProvider = Provider<BackupExporter>(
  (ref) => const BackupExporter(),
);

final backupImporterProvider = Provider<BackupImporter>(
  (ref) => const BackupImporter(),
);

/// What [BackupActions.exportToDocument] ended up doing; the page only needs to report it.
class BackupExportOutcome {
  const BackupExportOutcome.saved(BackupExportResult this.result)
    : cancelled = false,
      error = null;

  const BackupExportOutcome.cancelled()
    : result = null,
      cancelled = true,
      error = null;

  const BackupExportOutcome.empty()
    : result = null,
      cancelled = false,
      error = null;

  const BackupExportOutcome.failed(String this.error)
    : result = null,
      cancelled = false;

  /// Set only when the document was written.
  final BackupExportResult? result;
  final bool cancelled;
  final String? error;
}

class BackupActions {
  BackupActions(this._ref);

  final Ref _ref;

  Future<BackupExportResult> export(Set<BackupGroup> groups) async {
    final db = await _ref.read(subscriptionDatabaseProvider.future);
    final result = await _ref
        .read(backupExporterProvider)
        .export(
          BackupExportSource(
            settings: _ref.read(legacySettingsProvider),
            database: db,
          ),
          groups: groups,
        );
    return result;
  }

  /// Exports straight into the document the user picks, one chunk per group.
  ///
  /// The picker opens first: nothing is generated until there is somewhere to write it, and the
  /// JSON never exists as a whole string. An empty selection deletes the file again instead of
  /// leaving an empty document behind.
  Future<BackupExportOutcome> exportToDocument(Set<BackupGroup> groups) async {
    final bridge = _ref.read(platformBridgeProvider);
    final begun = await bridge.beginExportDocument(
      name:
          '${BackupFormat.fileNamePrefix}-'
          '${BackupFormat.stampOf(DateTime.now())}.json',
    );
    if (begun.cancelled) return const BackupExportOutcome.cancelled();
    final handle = begun.handle;
    if (handle == null) {
      return BackupExportOutcome.failed(
        begun.error ?? currentL10n.transferExportFailed,
      );
    }
    try {
      final db = await _ref.read(subscriptionDatabaseProvider.future);
      final result = await _ref
          .read(backupExporterProvider)
          .exportTo(
            (chunk) async {
              final written = await bridge.appendExportChunk(
                handle: handle,
                chunk: chunk,
              );
              if (!written) throw StateError(currentL10n.transferExportFailed);
            },
            BackupExportSource(
              settings: _ref.read(legacySettingsProvider),
              database: db,
            ),
            groups: groups,
          );
      if (result.isEmpty) {
        await bridge.abortExportDocument();
        return const BackupExportOutcome.empty();
      }
      final saved = await bridge.endExportDocument(handle);
      if (saved.saved) return BackupExportOutcome.saved(result);
      return BackupExportOutcome.failed(
        saved.error ?? currentL10n.transferExportFailed,
      );
    } catch (error) {
      await bridge.abortExportDocument();
      return BackupExportOutcome.failed('$error');
    }
  }

  /// Opens the system picker, parses and merges the picked file.
  Future<BackupImportResult> importFromDocument() async {
    final picked = await _ref.read(platformBridgeProvider).importDocument();
    if (picked.cancelled) return const BackupImportResult.cancelled();
    if (picked.error != null) return BackupImportResult.failed(picked.error!);
    final text = picked.text;
    if (text == null) return BackupImportResult.failed(currentL10n.backupReadFileFailed);
    return importText(text, sourceName: picked.name);
  }

  /// Merges backup text (WebDAV restore path, no file picker).
  Future<BackupImportResult> importText(
    String text, {
    String? sourceName,
  }) async {
    final db = await _ref.read(subscriptionDatabaseProvider.future);
    final result = await _ref
        .read(backupImporterProvider)
        .import(
          text,
          BackupImportTarget(
            store: _ref.read(legacyPrefsStoreProvider),
            database: db,
            dnsContainer: _ref.read(activeDataSetProvider).prefsContainer,
          ),
          sourceName: sourceName,
        );
    if (!result.failed && !result.cancelled) {
      _invalidate();
      _refreshIndexesIfNeeded(result);
    }
    return result;
  }

  /// Rule-writing groups went into the active database; recompile its tries so the next service
  /// start does not pay the compile itself (the stamp re-check would force it otherwise).
  void _refreshIndexesIfNeeded(BackupImportResult result) {
    const ruleGroups = {
      BackupGroup.subscriptions,
      BackupGroup.domainRules,
      BackupGroup.rewriteDomain,
      BackupGroup.rewriteCname,
      BackupGroup.addressRules,
    };
    if (result.outcomes.every(
      (outcome) => !ruleGroups.contains(outcome.group),
    )) {
      return;
    }
    refreshRuleIndexesForCurrentMode(_ref);
  }

  void _invalidate() {
    _ref.read(legacySettingsRevisionProvider.notifier).bump();
    _ref.read(subscriptionRevisionProvider.notifier).bump();
    _ref.read(dnsLogRevisionProvider.notifier).bump();
  }
}

final backupActionsProvider = Provider<BackupActions>(BackupActions.new);
