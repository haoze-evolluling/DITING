library;

import 'dart:convert';

import 'package:diting_shared/app/l10n/l10n.dart';

import 'package:diting_android/data/backup/backup_models.dart';
import 'package:diting_android/data/backup/rust_backup_core.dart';
import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/data/db/subscription_repository.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

part 'backup_import_apply.dart';
part 'backup_import_snapshot.dart';

class BackupGroupOutcome {
  const BackupGroupOutcome({
    required this.group,
    this.added = 0,
    this.skipped = 0,
    this.updated = 0,
    this.error,
  });

  final BackupGroup group;
  final int added;
  final int skipped;
  final int updated;

  final String? error;

  bool get failed => error != null;

  bool get isNoop => !failed && added == 0 && updated == 0;
}

class BackupImportResult {
  const BackupImportResult({
    required this.occurredAt,
    required this.outcomes,
    this.sourceName,
    this.cancelled = false,
    this.fatalError,
    this.subscriptionCount = 0,
  });

  const BackupImportResult.cancelled()
    : outcomes = const [],
      sourceName = null,
      cancelled = true,
      fatalError = null,
      occurredAt = null,
      subscriptionCount = 0;

  const BackupImportResult.failed(String this.fatalError)
    : outcomes = const [],
      sourceName = null,
      cancelled = false,
      occurredAt = null,
      subscriptionCount = 0;

  final DateTime? occurredAt;
  final List<BackupGroupOutcome> outcomes;
  final String? sourceName;
  final bool cancelled;

  final String? fatalError;

  final int subscriptionCount;

  bool get failed => fatalError != null;

  int get added => outcomes.fold(0, (sum, item) => sum + item.added);
  int get skipped => outcomes.fold(0, (sum, item) => sum + item.skipped);
  int get updated => outcomes.fold(0, (sum, item) => sum + item.updated);

  List<BackupGroupOutcome> get changed => [
    for (final outcome in outcomes)
      if (outcome.added + outcome.updated > 0) outcome,
  ];

  List<BackupGroupOutcome> get failedGroups => [
    for (final outcome in outcomes)
      if (outcome.failed) outcome,
  ];
}

class BackupImportTarget {
  const BackupImportTarget({
    required this.store,
    required this.database,
    this.dnsContainer,
  });

  final LegacyPrefsStore store;

  final Database? database;

  final String? dnsContainer;

  LegacySettings get settings =>
      LegacySettings(store, dnsContainer: dnsContainer);
}

class BackupImporter {
  const BackupImporter();

  Future<BackupImportResult> import(
    String content,
    BackupImportTarget target, {
    String? sourceName,
  }) async {
    final now = DateTime.now();
    final answer = RustBackupCore.instance.importDocument({
      'content': content,
      'nowMs': now.millisecondsSinceEpoch,
      'hasDatabase': target.database != null,
      'current': await _current(target),
    });

    final fatal = answer['fatal'];
    if (fatal != null) {
      return BackupImportResult.failed(_fatalMessage(fatal, content));
    }

    try {
      await _applyPlan(answer, target, now);
    } catch (error) {
      debugPrint('backup import failed while applying the plan: $error');
      return BackupImportResult.failed('$error');
    }

    final exportedAt = answer['exportedAt'];
    return BackupImportResult(
      occurredAt: exportedAt is int
          ? DateTime.fromMillisecondsSinceEpoch(exportedAt)
          : null,
      outcomes: [
        for (final entry in answer['outcomes'] as List? ?? const [])
          _outcome(entry),
      ],
      sourceName: sourceName,
      subscriptionCount: answer['subscriptionCount'] as int? ?? 0,
    );
  }

  static BackupGroupOutcome _outcome(Object? entry) {
    final record = entry is Map ? entry : const {};
    final group =
        BackupGroup.fromKey('${record['group']}') ?? BackupGroup.system;
    final error = record['error'];
    return BackupGroupOutcome(
      group: group,
      added: record['added'] as int? ?? 0,
      skipped: record['skipped'] as int? ?? 0,
      updated: record['updated'] as int? ?? 0,
      error: error is String ? _errorMessage(error) : null,
    );
  }

  static String _fatalMessage(Object? fatal, String content) {
    final record = fatal is Map ? fatal : const {};
    return switch ('${record['kind']}') {
      'empty' => currentL10n.backupErrEmpty,
      'notJson' => currentL10n.backupErrInvalidJson(_jsonError(content)),
      'rootNotObject' => currentL10n.backupErrRootNotObject,
      'notBackup' => currentL10n.backupErrNotDiting,
      'noVersion' => currentL10n.backupErrNoVersion,
      'tooNew' => currentL10n.backupErrVersionTooHigh(
        '${record['detail']}',
        BackupFormat.maxReadableVersion,
      ),
      'noData' => currentL10n.backupErrNoData,
      _ => currentL10n.backupErrNotDiting,
    };
  }

  static String _jsonError(String content) {
    try {
      jsonDecode(content.trim());
      return '';
    } on FormatException catch (error) {
      return error.message;
    }
  }

  static String _errorMessage(String kind) => switch (kind) {
    'providersNotArray' => currentL10n.backupErrProvidersNotArray,
    'bootstrapNotObject' => currentL10n.backupErrBootstrapNotObject,
    'cacheNotObject' => currentL10n.backupErrCacheNotObject,
    'outboundNotObject' => currentL10n.backupErrOutboundNotObject,
    'subsNotObject' => currentL10n.backupErrSubsNotObject,
    'noDbSubs' => currentL10n.backupErrNoRuleDbSubs,
    'rulesNotArray' => currentL10n.backupErrRulesNotArray,
    'noDbRules' => currentL10n.backupErrNoRuleDbRules,
    'rewriteNotArray' => currentL10n.backupErrRewriteNotArray,
    'noDbRewrite' => currentL10n.backupErrNoRuleDbRewrite,
    'addressNotArray' => currentL10n.backupErrAddressNotArray,
    'noDbAddress' => currentL10n.backupErrNoRuleDbAddress,
    'blockedNotObject' => currentL10n.backupErrBlockedNotObject,
    'appRulesNotObject' => currentL10n.backupErrAppRulesNotObject,
    'inspectionNotObject' => currentL10n.backupErrInspectionNotObject,
    'appearanceNotObject' => currentL10n.backupErrAppearanceNotObject,
    'systemNotObject' => currentL10n.backupErrSystemNotObject,
    _ => kind,
  };
}
