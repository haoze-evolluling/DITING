import 'dart:async';

import 'package:diting_android/data/db/datasets.dart';
import 'package:diting_android/data/db/app_database.dart';
import 'package:diting_android/data/db/preset_whitelist.dart';
import 'package:diting_android/data/db/rule_repository.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/data/native/runtime_events.dart';
import 'package:diting_android/data/prefs/legacy_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

typedef RuleBootstrap = ({RuleRepository? repository});

const _openBudget = Duration(seconds: 4);

Future<RuleBootstrap> bootstrapRules(
  DataSet dataSet,
  LegacySettings settings, {
  required int versionCode,
}) async {
  final databaseFile = dataSet.ruleDatabase;
  final opened = await _openRuleDatabase(databaseFile);
  final db = opened.database;
  if (db == null) {
    return (repository: null);
  }

  final repository = RuleRepository(db, sourceFile: databaseFile);
  if (!opened.recovered) {
    await seedPresetWhitelistIfNeeded(
      repository,
      settings,
      versionCode: versionCode,
    );
  }
  return (repository: repository);
}

Future<({Database? database, bool recovered})> _openRuleDatabase(
  String fileName,
) async {
  try {
    final db = await AppDatabase.open(fileName).timeout(_openBudget);
    return (database: db, recovered: false);
  } on TimeoutException {
    debugPrint('rule database open timed out: $fileName; retrying fresh');
    RuntimeEvents.error('db', 'rule.open_timeout file=$fileName');
  }
  try {
    final db = await AppDatabase.open(
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

Future<void> loadInitialRulesPaged(
  RuleRepository? repository,
  void Function(RuleKind kind, List<MockRule> page) onPage, {
  int pageSize = RuleRepository.loadPageSize,
  Future<void> Function()? beforePage,
}) async {
  if (repository == null) return;
  try {
    await repository.loadAllPaged(
      onPage,
      pageSize: pageSize,
      beforePage: beforePage,
    );
  } on DatabaseException catch (error) {
    debugPrint('rule load failed: $error');
  }
}

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
