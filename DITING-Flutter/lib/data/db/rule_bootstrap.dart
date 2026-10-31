import 'package:diting/data/db/datasets.dart';
import 'package:diting/data/db/legacy_database.dart';
import 'package:diting/data/db/preset_whitelist.dart';
import 'package:diting/data/db/rule_repository.dart';
import 'package:diting/data/mock_data.dart';
import 'package:diting/data/prefs/legacy_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

typedef RuleBootstrap = ({RuleRepository? repository});

/// Opens the data set's rule database and seeds its preset whitelist once per version code, so an
/// upgrade keeps the passthrough hosts Play services need; [versionCode] has no default.
///
/// [settings] must be the view of that data set, or the seed marker lands in another container.
/// Only the cheap parts live here: the full-table [RuleRepository.loadAll] that used to run before
/// `runApp` blocked the first frame for seconds on subscription-sized datasets, so it now runs via
/// [loadInitialRulesPaged] once the UI is up.
Future<RuleBootstrap> bootstrapRules(
  DataSet dataSet,
  LegacySettings settings, {
  required int versionCode,
}) async {
  final db = await LegacyDatabase.open(dataSet.ruleDatabase);
  if (db == null) {
    return (repository: null);
  }

  final repository = RuleRepository(db, sourceFile: dataSet.ruleDatabase);
  if (dataSet.seedsPresetWhitelist) {
    await seedPresetWhitelistIfNeeded(
      repository,
      settings,
      versionCode: versionCode,
    );
  }
  return (repository: repository);
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
    final content = await rootBundle.loadString('assets/https_passthrough.txt');
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
