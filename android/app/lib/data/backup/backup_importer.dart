/// Backup import: parse, validate and merge this app's `{format, version, data}` document.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:convert';

import 'package:diting_android/data/backup/backup_models.dart';
import 'package:diting_android/data/db/rule_repository.dart';
import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/data/db/subscription_repository.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/data/vpn/provider_store.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

part 'backup_import_lists.dart';
part 'backup_import_prefs.dart';
part 'backup_import_rules.dart';
part 'backup_import_settings.dart';

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

  /// Why the whole group failed; when set the counters are meaningless.
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

  /// The user cancelled file selection; this is not a failure.
  const BackupImportResult.cancelled()
    : outcomes = const [],
      sourceName = null,
      cancelled = true,
      fatalError = null,
      occurredAt = null,
      subscriptionCount = 0;

  /// The whole file could not be parsed (not a backup, too new, bad JSON).
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

  /// Why the whole file failed; when set, [outcomes] is empty.
  final String? fatalError;

  /// Number of subscriptions touched, used to prompt a rule refresh.
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

  /// Null on a fresh install; rule and subscription groups then report failure.
  final Database? database;

  /// Data set container the settings groups land in; null means the normal data set.
  final String? dnsContainer;

  LegacySettings get settings =>
      LegacySettings(store, dnsContainer: dnsContainer);
}

class BackupImporter {
  const BackupImporter();

  /// Parses and merges [content]; errors become [BackupImportResult.failed] instead of throwing,
  /// since the caller must explain the problem.
  Future<BackupImportResult> import(
    String content,
    BackupImportTarget target, {
    String? sourceName,
  }) async {
    final _ParsedBackup parsed;
    try {
      parsed = _parse(content);
    } on BackupFormatException catch (error) {
      return BackupImportResult.failed(error.message);
    }
    final data = parsed.data;
    final outcomes = <BackupGroupOutcome>[];
    var subscriptionCount = 0;

    for (final group in BackupGroup.values) {
      final value = data[group.key];
      // A group absent from the file is not an error; it may be unselected.
      if (value == null) continue;
      try {
        final outcome = await _applyGroup(group, value, target);
        outcomes.add(outcome);
        if (group == BackupGroup.subscriptions) {
          subscriptionCount = outcome.added;
        }
      } catch (error) {
        debugPrint('backup import failed for ${group.key}: $error');
        outcomes.add(BackupGroupOutcome(group: group, error: '$error'));
      }
    }

    // The selection travels inside the providers group so it stays out of the added/updated
    // counters.
    final providers = data[BackupGroup.providers.key];
    if (providers is Map && providers['selection'] is Map) {
      try {
        _applyProviderSelection(providers['selection'], target);
      } catch (error) {
        debugPrint('backup import failed for provider selection: $error');
      }
    }

    return BackupImportResult(
      occurredAt: parsed.exportedAt,
      outcomes: outcomes,
      sourceName: sourceName,
      subscriptionCount: subscriptionCount,
    );
  }

  /// Validates the envelope and returns its `data` object and `exportedAt`.
  ///
  /// Only this app's grouped document is accepted; the 1.4.3 flat root (`formatVersion` and the
  /// rule lists at the top level) is no longer read, which is why the writer stopped emitting it.
  _ParsedBackup _parse(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw BackupFormatException(currentL10n.backupErrEmpty);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException catch (error) {
      throw BackupFormatException(
        currentL10n.backupErrInvalidJson(error.message),
      );
    }
    if (decoded is! Map) {
      throw BackupFormatException(currentL10n.backupErrRootNotObject);
    }
    if (decoded['format'] != BackupFormat.magic) {
      throw BackupFormatException(currentL10n.backupErrNotDiting);
    }
    final exportedAt = decoded['exportedAt'];
    final timestamp = exportedAt is int
        ? DateTime.fromMillisecondsSinceEpoch(exportedAt)
        : null;
    final version = decoded['version'];
    if (version is! int) {
      throw BackupFormatException(currentL10n.backupErrNoVersion);
    }
    if (version > BackupFormat.maxReadableVersion) {
      throw BackupFormatException(
        currentL10n.backupErrVersionTooHigh(
          '$version',
          BackupFormat.maxReadableVersion,
        ),
      );
    }
    final data = decoded['data'];
    if (data is! Map) {
      throw BackupFormatException(currentL10n.backupErrNoData);
    }
    return _ParsedBackup(
      data: {for (final entry in data.entries) '${entry.key}': entry.value},
      exportedAt: timestamp,
    );
  }

  Future<BackupGroupOutcome> _applyGroup(
    BackupGroup group,
    Object? value,
    BackupImportTarget target,
  ) async => switch (group) {
    BackupGroup.providers => _importProviders(value, target),
    BackupGroup.bootstrap => _importBootstrap(value, target),
    BackupGroup.cache => _importCache(value, target),
    BackupGroup.outbound => _importOutbound(value, target),
    BackupGroup.subscriptions => await _importSubscriptions(value, target),
    BackupGroup.domainRules => await _importRules(value, target, group),
    BackupGroup.rewriteDomain => await _importRewrite(value, target, const {
      'IPv4',
      'IPv6',
    }, group),
    BackupGroup.rewriteCname => await _importRewrite(value, target, const {
      'CNAME',
    }, group),
    BackupGroup.addressRules => await _importAddressRules(value, target),
    BackupGroup.excluded => _importExcluded(value, target),
    BackupGroup.blocked => _importBlocked(value, target),
    BackupGroup.allowlist => _importAllowlist(value, target),
    BackupGroup.httpInspection => _importHttpInspection(value, target),
    BackupGroup.appearance => _importAppearance(value, target),
    BackupGroup.system => _importSystem(value, target),
  };
}

class _ParsedBackup {
  const _ParsedBackup({required this.data, required this.exportedAt});

  final Map<String, Object?> data;
  final DateTime? exportedAt;
}
