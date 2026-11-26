library;

import 'package:diting_android/app/l10n/l10n.dart';

import 'package:diting_android/data/backup/backup_exporter.dart';
import 'package:diting_android/data/backup/backup_importer.dart';
import 'package:diting_android/data/backup/backup_models.dart';
import 'package:diting_android/data/db/rule_dataset_providers.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/cleanup_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final backupExporterProvider = Provider<BackupExporter>(
  (ref) => const BackupExporter(),
);

final backupImporterProvider = Provider<BackupImporter>(
  (ref) => const BackupImporter(),
);

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

  final BackupExportResult? result;
  final bool cancelled;
  final String? error;
}

class BackupActions {
  BackupActions(this._ref);

  final Ref _ref;

  Future<BackupExportResult> export(Set<BackupGroup> groups) async {
    final db = await _ref.read(subscriptionDatabaseProvider.future);
    return _ref
        .read(backupExporterProvider)
        .export(
          BackupExportSource(
            settings: _ref.read(legacySettingsProvider),
            database: db,
          ),
          groups: groups,
        );
  }

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

  Future<BackupImportResult> importFromDocument() async {
    final picked = await _ref.read(platformBridgeProvider).importDocument();
    if (picked.cancelled) return const BackupImportResult.cancelled();
    if (picked.error != null) return BackupImportResult.failed(picked.error!);
    final text = picked.text;
    if (text == null) {
      return BackupImportResult.failed(currentL10n.backupReadFileFailed);
    }
    return importText(text, sourceName: picked.name);
  }

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
