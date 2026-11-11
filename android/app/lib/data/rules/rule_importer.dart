/// Writes parsed rules into the rule tables. Active = row and a source row enabled; dedupe is
/// explicit because older databases lack the unique index.
///
/// The statements, their dedupe predicates and the counters come from
/// `rust/diting-rule-store-core`; this file queues them into `sqflite` batches and reads back the
/// number of source rows each one wrote.
library;

import 'package:diting_android/data/db/rust_rule_store_core.dart';
import 'package:diting_android/data/rules/rule_models.dart';
import 'package:sqflite/sqflite.dart';

class RuleImportSummary {
  const RuleImportSummary({
    this.blockCount = 0,
    this.allowCount = 0,
    this.rewriteCount = 0,
    this.urlBlockCount = 0,
    this.urlAllowCount = 0,
    this.cosmeticCount = 0,
    this.duplicateCount = 0,
    this.invalidCount = 0,
    this.unsupportedCount = 0,
    this.typeSkippedCount = 0,
    this.badfilteredCount = 0,
  });

  final int blockCount;
  final int allowCount;
  final int rewriteCount;
  final int urlBlockCount;
  final int urlAllowCount;
  final int cosmeticCount;
  final int duplicateCount;
  final int invalidCount;
  final int unsupportedCount;
  final int typeSkippedCount;
  final int badfilteredCount;

  /// Rules written or reused; the only count safe to show as "N imported".
  int get insertedCount =>
      blockCount + allowCount + rewriteCount + urlBlockCount + urlAllowCount;

  /// Parsed but not stored: the engine has no injection path for cosmetic rules.
  int get notAppliedCount => cosmeticCount;

  bool get isEmpty => insertedCount == 0;
}

String subscriptionSourceTag(int subscriptionId) => 'sub_$subscriptionId';

class RuleImporter {
  RuleImporter(this._db, {this.chunkSize = 1000});

  /// Rows per orphan-delete page, read from the core so the sweep and its tests agree on one
  /// number.
  static final int orphanPageSize = _orphanPageSize();

  static int _orphanPageSize() {
    final plan = RustRuleStoreCore.instance.plan({
      'op': 'removeSource',
      'source': '',
    });
    for (final orphan in plan['orphans'] as List? ?? const []) {
      if (orphan is! Map) continue;
      final args = orphan['selectArgs'];
      if (args is List && args.isNotEmpty && args.first is int) {
        return args.first as int;
      }
    }
    return 2000;
  }

  final Database _db;
  final int chunkSize;

  /// Imports parsed rules under [source]; [kind] is `SubscriptionKind.storageValue`, [enabled] the
  /// subscription switch.
  Future<RuleImportSummary> import(
    CategorizedRules parsed, {
    required String source,
    required String kind,
    required bool enabled,
  }) async {
    final plan = RustRuleStoreCore.instance.plan({
      'op': 'import',
      'source': source,
      'kind': kind,
      'enabled': enabled,
      'chunkSize': chunkSize,
      'nowMs': DateTime.now().millisecondsSinceEpoch,
      'parsed': _parsedJson(parsed),
    });

    final counts = <String, int>{};
    for (final batch in plan['batches'] as List? ?? const []) {
      if (batch is! Map) continue;
      final family = '${batch['family']}';
      counts[family] =
          (counts[family] ?? 0) + await _runBatch(batch['steps'] as List? ?? const []);
    }

    final summary = (plan['summary'] as Map?) ?? const {};
    return RuleImportSummary(
      blockCount: counts['block'] ?? 0,
      allowCount: counts['allow'] ?? 0,
      rewriteCount: counts['rewrite'] ?? 0,
      urlBlockCount: counts['urlBlock'] ?? 0,
      urlAllowCount: counts['urlAllow'] ?? 0,
      cosmeticCount: summary['cosmetic'] as int? ?? 0,
      duplicateCount: summary['duplicate'] as int? ?? 0,
      invalidCount: summary['invalid'] as int? ?? 0,
      unsupportedCount: summary['unsupported'] as int? ?? 0,
      typeSkippedCount: summary['typeSkipped'] as int? ?? 0,
      badfilteredCount: summary['badfiltered'] as int? ?? 0,
    );
  }

  /// Deletes one source's rules. Only source rows go: a rule row may be shared.
  ///
  /// Two short steps instead of one long transaction: the source rows go in a single statement set,
  /// then the orphans are swept in bounded id-range batches. A `DELETE ... WHERE id NOT IN
  /// (SELECT ...)` over a subscription-sized table held the write lock for minutes, which starved
  /// every other reader and writer of `diting_database` (see the 2026-10-27 log: 183 failed
  /// `PRAGMA journal_mode` probes, no successful open at all).
  Future<void> removeRulesBySource(String source) async {
    final plan = RustRuleStoreCore.instance.plan({
      'op': 'removeSource',
      'source': source,
    });
    await _db.transaction((txn) async {
      for (final step in plan['steps'] as List? ?? const []) {
        if (step is! Map) continue;
        await txn.rawDelete(
          '${step['sql']}',
          sqlArgs(step['args']),
        );
      }
    });
    for (final orphan in plan['orphans'] as List? ?? const []) {
      if (orphan is Map) await _sweepOrphans(orphan);
    }
  }

  /// Sets `enabled` on all source rows of [source]; the shared rule row keeps its own flag.
  Future<void> setSourceEnabled(String source, bool enabled) async {
    final plan = RustRuleStoreCore.instance.plan({
      'op': 'setSourceEnabled',
      'source': source,
      'enabled': enabled,
    });
    await _db.transaction((txn) async {
      for (final step in plan['steps'] as List? ?? const []) {
        if (step is! Map) continue;
        await txn.rawUpdate(
          '${step['sql']}',
          sqlArgs(step['args']),
        );
      }
    });
  }

  /// Drops rule rows that no source references; they would only inflate counts.
  ///
  /// Each page is its own transaction, so the write lock is never held longer than one page's worth
  /// of deletes, and the loop yields so queued reads still get a turn.
  Future<void> _sweepOrphans(Map orphan) async {
    final selectSql = '${orphan['selectSql']}';
    final selectArgs = sqlArgs(orphan['selectArgs']);
    final deletePrefix = '${orphan['deletePrefix']}';
    while (true) {
      final removed = await _db.transaction<int>((txn) async {
        final rows = await txn.rawQuery(selectSql, selectArgs);
        if (rows.isEmpty) return 0;
        final ids = [for (final row in rows) row['id'] as int];
        final placeholders = List.filled(ids.length, '?').join(',');
        await txn.rawDelete('$deletePrefix$placeholders)', ids);
        return ids.length;
      });
      if (removed == 0) return;
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Runs one batch inside a transaction, with all statements queued in a single platform round
  /// trip: three statements per rule in one call instead of three calls per rule, which is what made
  /// a 1000-rule chunk take seconds and hold the write lock meanwhile.
  ///
  /// Returns the number of source rows written: the statement the core marks `changes` is followed
  /// by `SELECT changes()`, exactly like the legacy loop.
  Future<int> _runBatch(List steps) async {
    if (steps.isEmpty) return 0;
    var inserted = 0;
    await _db.transaction((txn) async {
      final batch = txn.batch();
      final counted = <int>[];
      var index = 0;
      for (final step in steps) {
        if (step is! Map) continue;
        final sql = '${step['sql']}';
        final args = sqlArgs(step['args']);
        if (sql.startsWith('INSERT')) {
          batch.rawInsert(sql, args);
        } else if (sql.startsWith('UPDATE') || sql.startsWith('DELETE')) {
          batch.rawUpdate(sql, args);
        } else {
          batch.rawQuery(sql, args);
        }
        index++;
        if (step['changes'] == true) {
          batch.rawQuery('SELECT changes() AS c');
          counted.add(index);
          index++;
        }
      }
      final results = await batch.commit(noResult: false);
      for (final position in counted) {
        final rows = results[position];
        if (rows is List && rows.isNotEmpty) {
          inserted += (rows.first as Map)['c'] as int? ?? 0;
        }
      }
    });
    return inserted;
  }

  /// The parsed document, field for field; the core reads these snake-free names.
  static Map<String, Object?> _parsedJson(CategorizedRules parsed) => {
    'blockRules': [for (final rule in parsed.blockRules) _ruleJson(rule)],
    'allowRules': [for (final rule in parsed.allowRules) _ruleJson(rule)],
    'rewriteRules': [
      for (final rule in parsed.rewriteRules)
        {
          'pattern': rule.pattern,
          'targetType': rule.targetType,
          'targetValue': rule.targetValue,
          'rawLine': rule.rawLine,
        },
    ],
    'urlBlockRules': [for (final rule in parsed.urlBlockRules) _urlJson(rule)],
    'urlAllowRules': [for (final rule in parsed.urlAllowRules) _urlJson(rule)],
    'cosmeticRules': [
      for (final rule in parsed.cosmeticRules)
        {'domain': rule.domain, 'selector': rule.selector},
    ],
    'duplicateCount': parsed.duplicateCount,
    'invalidCount': parsed.invalidCount,
    'unsupportedCount': parsed.unsupportedCount,
    'badfilteredCount': parsed.badfilteredCount,
  };

  static Map<String, Object?> _ruleJson(ParsedRule rule) => {
    'pattern': rule.pattern,
    'rawLine': rule.rawLine,
    'important': rule.important,
    'appScope': rule.appScope,
    'appInverted': rule.appInverted,
    'isWildcard': rule.isWildcard,
    'denyallow': rule.denyallow,
    'isRegex': rule.isRegex,
    'dnsType': rule.dnsType,
  };

  static Map<String, Object?> _urlJson(ParsedUrlRule rule) => {
    'pattern': rule.pattern,
    'rawLine': rule.rawLine,
    'isAllow': rule.isAllow,
    'appScope': rule.appScope,
  };
}
