library;

import 'dart:convert';
import 'dart:io';

import 'package:diting_shared/data/db/app_database.dart';
import 'package:diting_shared/data/db/legacy_storage_source.dart';
import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:diting_shared/data/db/storage_v2_copy.dart';
import 'package:diting_shared/data/db/storage_v2_verify.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class StorageV2Progress {
  const StorageV2Progress({
    required this.phase,
    required this.current,
    required this.total,
    this.database,
    this.table,
  });

  final String phase;
  final int current;
  final int total;
  final String? database;
  final String? table;
}

class StorageV2Result {
  const StorageV2Result._({
    required this.ready,
    this.deferred = false,
    this.error,
    this.report,
  });

  const StorageV2Result.ready([Map<String, Object?>? report])
    : this._(ready: true, report: report);

  factory StorageV2Result.deferred(String reason) =>
      StorageV2Result._(ready: false, deferred: true, error: reason);

  factory StorageV2Result.failed(Object error) =>
      StorageV2Result._(ready: false, error: '$error');

  final bool ready;
  final bool deferred;
  final String? error;
  final Map<String, Object?>? report;
}

class StorageV2Exception implements Exception {
  const StorageV2Exception(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class StorageV2Native {
  Future<void> closeConnections();

  Future<Map<String, Object?>> verifyDatabases({
    required List<String> logDatabases,
    required List<String> ruleDatabases,
  });

  Future<void> clearRuleIndexes();
}

class MethodChannelStorageV2Native implements StorageV2Native {
  const MethodChannelStorageV2Native({this.channel = _channel});

  static const _channel = MethodChannel('com.haoze.diting/storage');

  final MethodChannel channel;

  @override
  Future<void> closeConnections() async {
    try {
      await channel.invokeMethod<void>('closeConnections');
    } on MissingPluginException {
    }
  }

  @override
  Future<Map<String, Object?>> verifyDatabases({
    required List<String> logDatabases,
    required List<String> ruleDatabases,
  }) async {
    try {
      final answer = await channel.invokeMethod<Map<Object?, Object?>>(
        'verify',
        {
          'logDatabases': logDatabases,
          'ruleDatabases': ruleDatabases,
        },
      );
      return answer?.cast<String, Object?>() ?? const {};
    } on MissingPluginException {
      return const {'ok': true, 'skipped': true};
    }
  }

  @override
  Future<void> clearRuleIndexes() async {
    try {
      await channel.invokeMethod<void>('clearRuleIndexes');
    } on MissingPluginException {
    }
  }
}

class NoopStorageV2Native implements StorageV2Native {
  const NoopStorageV2Native();

  @override
  Future<void> closeConnections() async {}

  @override
  Future<Map<String, Object?>> verifyDatabases({
    required List<String> logDatabases,
    required List<String> ruleDatabases,
  }) async => const {'ok': true};

  @override
  Future<void> clearRuleIndexes() async {}
}

Future<bool> storageV2FilesReady() async {
  for (final kind in DatabaseKind.values) {
    final db = await AppDatabase.open(kind.fileName, create: false);
    if (db == null) return false;
    await db.close();
  }
  return true;
}

Future<bool> hasLegacyStores() async {
  final String directory;
  try {
    directory = await getDatabasesPath();
  } on StateError {
    return false;
  }
  for (final name in LegacyStorageSource.allOldDatabases) {
    if (await File(p.join(directory, name)).exists()) return true;
  }
  return false;
}

bool storageV2GateRequired({
  required int state,
  required bool filesReady,
  required bool legacyStoresPresent,
}) {
  if (StorageContract.isReadyState(state) && filesReady) return false;
  if (state == StorageContract.stateIdle) {
    return !filesReady && legacyStoresPresent;
  }
  return true;
}

Future<StorageV2Result> ensureStorageV2(
  LegacyPrefsStore store, {
  bool dataPlaneRunning = false,
  void Function(StorageV2Progress progress)? onProgress,
  StorageV2Native native = const MethodChannelStorageV2Native(),
}) async {
  final settings = LegacySettings(store);
  final state = settings.storageV2State;
  if (state >= StorageContract.stateVerified &&
      await storageV2FilesReady()) {
    await _removeStaleLock(settings);
    return const StorageV2Result.ready();
  }
  if (state < StorageContract.stateVerified && await storageV2FilesReady()) {
    await settings.commitStorageV2State(StorageContract.stateVerified);
    settings.setStorageV2CompletedAt(DateTime.now());
    settings.setStorageV2Error(null);
    await _removeStaleLock(settings);
    return const StorageV2Result.ready();
  }
  if (state != StorageContract.stateIdle) {
    settings.setStorageV2State(StorageContract.stateIdle);
  }
  if (dataPlaneRunning) {
    const reason = 'a running data plane keeps the old databases in use';
    settings.setStorageV2Error(reason);
    return StorageV2Result.deferred(reason);
  }

  final directory = await getDatabasesPath();
  await settings.commitStorageV2State(StorageContract.stateCopying);
  settings.setStorageV2Error(null);
  settings.setStorageV2Report(null);
  await _writeLock(directory);
  final report = <String, Object?>{'databases': <Object?>[], 'startedAt': DateTime.now().toIso8601String()};
  try {
    await _deleteTargets(directory);
    final plans = storageV2CopyPlans();
    final verified = <Map<String, Object?>>[];
    for (var index = 0; index < plans.length; index++) {
      final plan = plans[index];
      onProgress?.call(
        StorageV2Progress(
          phase: 'copy',
          current: index,
          total: plans.length,
          database: plan.target.fileName,
        ),
      );
      final db = await AppDatabase.open(plan.target.fileName);
      if (db == null) {
        throw StorageV2Exception(
          'cannot create ${plan.target.fileName}',
        );
      }
      try {
        final copy = await copyStoragePlan(
          db,
          p.join(directory, plan.source),
          plan,
          onTable: (table, tableIndex, tableTotal) {
            onProgress?.call(
              StorageV2Progress(
                phase: 'copy',
                current: index,
                total: plans.length,
                database: plan.target.fileName,
                table: table,
              ),
            );
          },
        );
        final verification = await verifyStorageDatabase(db, copy);
        verified.add(verification);
      } finally {
        await db.close();
      }
    }
    onProgress?.call(
      StorageV2Progress(phase: 'native', current: plans.length, total: plans.length),
    );
    final nativeAnswer = await native.verifyDatabases(
      logDatabases: [
        for (final kind in const [
          DatabaseKind.normalLogs,
          DatabaseKind.expressLogs,
        ])
          kind.fileName,
      ],
      ruleDatabases: [
        for (final kind in const [
          DatabaseKind.normalRules,
          DatabaseKind.expressRules,
        ])
          kind.fileName,
      ],
    );
    if (nativeAnswer['ok'] != true) {
      throw StorageV2Exception(
        'native verification failed: ${jsonEncode(nativeAnswer)}',
      );
    }
    report['databases'] = verified;
    report['native'] = nativeAnswer;
    report['completedAt'] = DateTime.now().toIso8601String();
    await settings.commitStorageV2State(StorageContract.stateVerified);
    settings.setStorageV2CompletedAt(DateTime.now());
    settings.setStorageV2Report(jsonEncode(report));
    settings.setStorageV2Error(null);
    await _removeLock(directory);
    return StorageV2Result.ready(report);
  } catch (error, stack) {
    debugPrint('storage v2 migration failed: $error');
    debugPrint('$stack');
    report['error'] = '$error';
    settings.setStorageV2State(StorageContract.stateIdle);
    settings.setStorageV2Error('$error');
    settings.setStorageV2Report(jsonEncode(report));
    await _deleteTargets(directory);
    await _removeLock(directory);
    return StorageV2Result.failed(error);
  }
}

Future<StorageV2Result> discardStorageV2(
  LegacyPrefsStore store, {
  StorageV2Native native = const MethodChannelStorageV2Native(),
}) async {
  final settings = LegacySettings(store);
  final directory = await getDatabasesPath();
  await settings.commitStorageV2State(StorageContract.stateCopying);
  await _writeLock(directory);
  try {
    await _deleteTargets(directory);
    final verified = <Map<String, Object?>>[];
    for (final kind in DatabaseKind.values) {
      final db = await AppDatabase.open(kind.fileName);
      if (db == null) throw StorageV2Exception('cannot create ${kind.fileName}');
      try {
        final copy = StorageCopyResult(
          plan: StorageCopyPlan(target: kind, source: '', tables: const []),
          sourceMissing: true,
          tables: const [],
        );
        verified.add(await verifyStorageDatabase(db, copy));
      } finally {
        await db.close();
      }
    }
    final nativeAnswer = await native.verifyDatabases(
      logDatabases: [
        for (final kind in const [
          DatabaseKind.normalLogs,
          DatabaseKind.expressLogs,
        ])
          kind.fileName,
      ],
      ruleDatabases: [
        for (final kind in const [
          DatabaseKind.normalRules,
          DatabaseKind.expressRules,
        ])
          kind.fileName,
      ],
    );
    if (nativeAnswer['ok'] != true) {
      throw StorageV2Exception('native verification failed');
    }
    await settings.commitStorageV2State(StorageContract.stateVerified);
    settings.setStorageV2CompletedAt(DateTime.now());
    settings.setStorageV2Report(jsonEncode({
      'discarded': true,
      'databases': verified,
      'native': nativeAnswer,
    }));
    settings.setStorageV2Error(null);
    await _removeLock(directory);
    return const StorageV2Result.ready();
  } catch (error) {
    settings.setStorageV2State(StorageContract.stateIdle);
    settings.setStorageV2Error('$error');
    await _deleteTargets(directory);
    await _removeLock(directory);
    return StorageV2Result.failed(error);
  }
}

Future<StorageV2Result> cleanupStorageV2(
  LegacyPrefsStore store, {
  required bool dataPlaneRunning,
  StorageV2Native native = const MethodChannelStorageV2Native(),
}) async {
  final settings = LegacySettings(store);
  if (settings.storageV2State < StorageContract.stateVerified) {
    return const StorageV2Result._(ready: false, error: 'storage not verified');
  }
  if (settings.storageV2State >= StorageContract.stateCleaned) {
    return const StorageV2Result.ready();
  }
  if (dataPlaneRunning) {
    return StorageV2Result.deferred('a data plane is still running');
  }
  try {
    await native.closeConnections();
    await _deleteOldDatabases();
    await native.clearRuleIndexes();
    for (final key in LegacyStorageSource.oldPreferenceKeys) {
      store.remove(StorageContract.settingsContainer, key);
    }
    await _removeStaleLock(settings);
    await settings.commitStorageV2State(StorageContract.stateCleaned);
    return const StorageV2Result.ready();
  } catch (error) {
    debugPrint('storage v2 cleanup failed: $error');
    settings.setStorageV2Error('$error');
    return StorageV2Result.failed(error);
  }
}

Future<void> sweepLegacyDatabases({
  required bool dataPlaneRunning,
  StorageV2Native native = const MethodChannelStorageV2Native(),
}) async {
  if (dataPlaneRunning) return;
  try {
    await native.closeConnections();
    await _deleteOldDatabases();
  } catch (error) {
    debugPrint('legacy storage sweep skipped: $error');
  }
}

Future<void> _deleteOldDatabases() async {
  final String directory;
  try {
    directory = await getDatabasesPath();
  } on StateError {
    return;
  }
  for (final name in LegacyStorageSource.allOldDatabases) {
    await AppDatabase.deleteWithSidecars(directory, name);
  }
}

Future<void> _deleteTargets(String directory) async {
  for (final kind in DatabaseKind.values) {
    await AppDatabase.deleteWithSidecars(directory, kind.fileName);
  }
}

Future<void> _writeLock(String directory) async {
  try {
    await File(p.join(directory, StorageContract.migrationLockName))
        .writeAsString('${DateTime.now().millisecondsSinceEpoch}');
  } catch (error) {
    debugPrint('storage lock write failed: $error');
  }
}

Future<void> _removeLock(String directory) async {
  try {
    final file = File(p.join(directory, StorageContract.migrationLockName));
    if (await file.exists()) await file.delete();
  } catch (error) {
    debugPrint('storage lock cleanup failed: $error');
  }
}

Future<void> _removeStaleLock(LegacySettings settings) async {
  if (settings.storageV2State == StorageContract.stateCopying) return;
  try {
    final directory = await getDatabasesPath();
    await _removeLock(directory);
  } on StateError {
  }
}
