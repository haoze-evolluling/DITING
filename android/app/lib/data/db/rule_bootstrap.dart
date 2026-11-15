import 'dart:async';

import 'package:diting_shared/data/db/datasets.dart';
import 'package:diting_shared/data/db/legacy_database.dart';
import 'package:diting_android/data/db/preset_whitelist.dart';
import 'package:diting_android/data/db/rule_repository.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/data/native/runtime_events.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

typedef RuleBootstrap = ({RuleRepository? repository});

/// How long the rule database is allowed to take before it is treated as wedged. Opening an existing
/// file at the current schema version is a well-under-a-second operation (a first-run seed measured
/// ~140 ms), so anything this slow is a stuck connection, not real work.
const _openBudget = Duration(seconds: 4);

/// Opens the data set's rule database and seeds its preset whitelist once per version code, so an
/// upgrade keeps the passthrough hosts Play services need; [versionCode] has no default.
///
/// [settings] must be the view of that data set, or the seed marker lands in another container.
/// Only the cheap parts live here: the full-table [RuleRepository.loadAll] that used to run before
/// `runApp` blocked the first frame for seconds on subscription-sized datasets, so it now runs via
/// [loadInitialRulesPaged] once the UI is up.
///
/// The open is also bounded. sqflite keeps its open-database registry in a `static` map shared by
/// every `FlutterEngine` in the process; when a tunnel service keeps the process alive, each
/// re-entered activity starts a fresh engine whose `main()` runs this again, and the connection the
/// previous engine left behind is handed straight back. If that connection was abandoned mid
/// transaction it never yields, every following call (the `PRAGMA`/version probe `openDatabase`
/// makes) is queued behind it, and because `main()` awaits this before `runApp` the only symptom is
/// the launch logo never going away. So on a timeout we retry on a brand-new connection instead of
/// waiting forever; a read-only handle is far better than a frozen first frame.
Future<RuleBootstrap> bootstrapRules(
  DataSet dataSet,
  LegacySettings settings, {
  required int versionCode,
}) async {
  final opened = await _openRuleDatabase(dataSet.ruleDatabase);
  final db = opened.database;
  if (db == null) {
    return (repository: null);
  }

  final repository = RuleRepository(db, sourceFile: dataSet.ruleDatabase);
  // A recovered connection is read-only in spirit: re-running the preset seed on it could block on
  // the very transaction that wedged the original open, so only seed a normal open.
  if (dataSet.seedsPresetWhitelist && !opened.recovered) {
    await seedPresetWhitelistIfNeeded(
      repository,
      settings,
      versionCode: versionCode,
    );
  }
  return (repository: repository);
}

/// Opens [fileName] with a timeout, falling back to a fresh connection when the reusable one is
/// wedged. `recovered` reports that the fallback ran, so the caller skips writes on it.
Future<({Database? database, bool recovered})> _openRuleDatabase(
  String fileName,
) async {
  try {
    final db = await LegacyDatabase.open(fileName).timeout(_openBudget);
    return (database: db, recovered: false);
  } on TimeoutException {
    debugPrint('rule database open timed out: $fileName; retrying fresh');
    RuntimeEvents.error('db', 'rule.open_timeout file=$fileName');
  }
  try {
    final db = await LegacyDatabase.open(
      fileName,
      singleInstance: false,
    ).timeout(_openBudget);
    return (database: db, recovered: true);
  } on TimeoutException {
    debugPrint('rule database fresh open timed out: $fileName');
    RuntimeEvents.error('db', 'rule.open_timeout_fresh file=$fileName');
    return (database: null, recovered: true);
  }
}

/// Paged fill for `initialRulesProvider`: [onPage] receives each page as it arrives, so the caller
/// can publish it right away instead of holding a subscription's whole table in memory. A failed
/// read stops the fill with what already arrived rather than throwing away the pages on screen.
Future<void> loadInitialRulesPaged(
  RuleRepository? repository,
  void Function(RuleKind kind, List<MockRule> page) onPage, {
  int pageSize = RuleRepository.loadPageSize,
}) async {
  if (repository == null) return;
  try {
    await repository.loadAllPaged(onPage, pageSize: pageSize);
  } on DatabaseException catch (error) {
    debugPrint('rule load failed: $error');
  }
}

/// Public because a data set opened after startup (mode switch) seeds itself through the same
/// marker check.
Future<void> seedPresetWhitelistIfNeeded(
  RuleRepository repository,
  LegacySettings settings, {
  required int versionCode,
}) async {
  final target = versionCode * 1000 + 2;
  if (settings.defaultWhitelistInitialized &&
      settings.defaultWhitelistSeededVersion == target) {
    return;
  }
  try {
    final content = await rootBundle.loadString('packages/diting_shared/assets/https_passthrough.txt');
    final entries = parsePresetWhitelist(content);
    if (entries.isEmpty) {
      // Never mark an empty asset as seeded: the next launch must retry.
      debugPrint('preset whitelist asset produced no entries');
      return;
    }
    await repository.resetPresetWhitelist(entries);
    settings.markDefaultWhitelistSeeded(versionCode);
  } on FlutterError catch (error) {
    debugPrint('preset whitelist asset missing: $error');
  } on DatabaseException catch (error) {
    debugPrint('preset whitelist seed failed: $error');
  }
}
