/// Optional cleanup of the pre-split database files.
///
/// The split migration is additive: it never rewrites a legacy file, so a migrated install keeps
/// `diting_database`, `diting_express` and `diting_server_logs` as byte-for-byte copies next to the
/// new stores. They are no longer read once `storage_layout_version` is set, but they still hold
/// the pre-migration logs and take the same disk space twice.
///
/// Reclaiming is deliberately separate from the migration so a failed or interrupted upgrade keeps
/// a working fallback. Callers decide when the grace period is over:
///
/// * startup uses [reclaimLegacyStorageIfDue] (a week after the split committed), and
/// * "clear all local data" uses [reclaimLegacyDatabases] because the user asked for a wipe.
library;

import 'dart:io';

import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Default delay between a successful split and the automatic removal of the legacy copies.
const storageReclaimGracePeriod = Duration(days: 7);

/// Existing reclaimable legacy files and their total size (database + WAL + SHM).
///
/// Returns an empty map when the host has no sqflite implementation (tests, desktop) or when
/// nothing is left to reclaim.
Future<Map<String, int>> legacyDatabaseSizes() async {
  final String directory;
  try {
    directory = await getDatabasesPath();
  } on StateError {
    return const {};
  }
  final sizes = <String, int>{};
  for (final name in StorageContract.reclaimableLegacyDatabases) {
    var total = 0;
    for (final suffix in const ['', '-wal', '-shm']) {
      final file = File(p.join(directory, '$name$suffix'));
      if (await file.exists()) total += await file.length();
    }
    if (total > 0) sizes[name] = total;
  }
  return sizes;
}

/// Deletes the stale legacy files and reports the bytes reclaimed.
///
/// Refuses to run on the legacy layout or while a data plane is alive: in the first case the files
/// are the live stores, and in the second a service may still hold a handle from before the switch.
/// `diting_dns_rules` is never touched — it kept its legacy name because it is the server mode's
/// live rules database in both layouts.
Future<int> reclaimLegacyDatabases({
  required bool split,
  required bool dataPlaneRunning,
}) async {
  if (!split || dataPlaneRunning) return 0;
  final sizes = await legacyDatabaseSizes();
  if (sizes.isEmpty) return 0;
  final String directory;
  try {
    directory = await getDatabasesPath();
  } on StateError {
    return 0;
  }
  var freed = 0;
  for (final entry in sizes.entries) {
    try {
      await deleteDatabase(p.join(directory, entry.key));
      freed += entry.value;
    } catch (error) {
      debugPrint('storage reclaim failed for ${entry.key}: $error');
    }
  }
  return freed;
}

/// Startup path: reclaim only after the split has been active for [gracePeriod].
///
/// The grace period is what makes an interrupted migration harmless — during it the legacy files
/// are still a usable fallback, after it they are only duplicate data.
Future<int> reclaimLegacyStorageIfDue(
  LegacyPrefsStore store, {
  required bool dataPlaneRunning,
  Duration gracePeriod = storageReclaimGracePeriod,
}) async {
  final settings = LegacySettings(store);
  if (!settings.storageLayout.isSplit || dataPlaneRunning) return 0;
  final completed = settings.storageSplitCompletedAt;
  if (completed == null ||
      DateTime.now().difference(completed) < gracePeriod) {
    return 0;
  }
  return reclaimLegacyDatabases(split: true, dataPlaneRunning: false);
}
