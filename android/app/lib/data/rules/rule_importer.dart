/// Writes parsed rules into the rule tables. Active = row and a source row enabled; dedupe is
/// explicit because older databases lack the unique index.
library;

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

/// Families the target table accepts: `domain` rows take block/allow, `hosts` subs take none of the
/// allow/url/cosmetic families.
bool _acceptsDomainOnlyFamilies(String kind) => kind != 'hosts';

class RuleImporter {
  RuleImporter(this._db, {this.chunkSize = 1000});

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
    final domainOnly = _acceptsDomainOnlyFamilies(kind);

    var insertedBlock = 0;
    var insertedAllow = 0;
    var insertedRewrite = 0;
    var insertedUrlBlock = 0;
    var insertedUrlAllow = 0;
    var typeSkipped = 0;

    final blockBatch = <ParsedRule>[];
    final allowBatch = <ParsedRule>[];
    final rewriteBatch = <ParsedRewriteRule>[];
    final urlBlockBatch = <ParsedUrlRule>[];
    final urlAllowBatch = <ParsedUrlRule>[];

    Future<void> flushBlock() async {
      if (blockBatch.isEmpty) return;
      insertedBlock += await _insertBlockRules(
        blockBatch,
        source: source,
        enabled: enabled,
      );
      blockBatch.clear();
    }

    Future<void> flushAllow() async {
      if (allowBatch.isEmpty) return;
      insertedAllow += await _insertAllowRules(
        allowBatch,
        source: source,
        enabled: enabled,
      );
      allowBatch.clear();
    }

    Future<void> flushRewrite() async {
      if (rewriteBatch.isEmpty) return;
      insertedRewrite += await _insertRewriteRules(
        rewriteBatch,
        source: source,
        enabled: enabled,
      );
      rewriteBatch.clear();
    }

    Future<void> flushUrlBlock() async {
      if (urlBlockBatch.isEmpty) return;
      insertedUrlBlock += await _insertUrlRules(
        urlBlockBatch,
        source: source,
        enabled: enabled,
      );
      urlBlockBatch.clear();
    }

    Future<void> flushUrlAllow() async {
      if (urlAllowBatch.isEmpty) return;
      insertedUrlAllow += await _insertUrlRules(
        urlAllowBatch,
        source: source,
        enabled: enabled,
      );
      urlAllowBatch.clear();
    }

    for (final rule in parsed.blockRules) {
      blockBatch.add(rule);
      if (blockBatch.length >= chunkSize) await flushBlock();
    }
    if (domainOnly) {
      for (final rule in parsed.allowRules) {
        allowBatch.add(rule);
        if (allowBatch.length >= chunkSize) await flushAllow();
      }
    } else {
      typeSkipped += parsed.allowRules.length;
    }
    for (final rule in parsed.rewriteRules) {
      rewriteBatch.add(rule);
      if (rewriteBatch.length >= chunkSize) await flushRewrite();
    }
    if (domainOnly) {
      for (final rule in parsed.urlBlockRules) {
        urlBlockBatch.add(rule);
        if (urlBlockBatch.length >= chunkSize) await flushUrlBlock();
      }
      for (final rule in parsed.urlAllowRules) {
        urlAllowBatch.add(rule);
        if (urlAllowBatch.length >= chunkSize) await flushUrlAllow();
      }
    } else {
      typeSkipped += parsed.urlBlockRules.length + parsed.urlAllowRules.length;
    }
    await flushBlock();
    await flushAllow();
    await flushRewrite();
    await flushUrlBlock();
    await flushUrlAllow();

    return RuleImportSummary(
      blockCount: insertedBlock,
      allowCount: insertedAllow,
      rewriteCount: insertedRewrite,
      urlBlockCount: insertedUrlBlock,
      urlAllowCount: insertedUrlAllow,
      cosmeticCount: domainOnly ? parsed.cosmeticRules.length : 0,
      duplicateCount: parsed.duplicateCount,
      invalidCount: parsed.invalidCount,
      unsupportedCount: parsed.unsupportedCount,
      typeSkippedCount: typeSkipped,
      badfilteredCount: parsed.badfilteredCount,
    );
  }

  /// Deletes one source's rules. Only source rows go: a rule row may be shared.
  ///
  /// Two short steps instead of one long transaction: the source rows go in a single statement
  /// set, then the orphans are swept in bounded id-range batches. A `DELETE ... WHERE id NOT IN
  /// (SELECT ...)` over a subscription-sized table held the write lock for minutes, which starved
  /// every other reader and writer of `diting_database` (see the 2026-10-27 log: 183 failed
  /// `PRAGMA journal_mode` probes, no successful open at all).
  Future<void> removeRulesBySource(String source) async {
    await _db.transaction((txn) async {
      for (final table in _sourceTables) {
        await txn.delete(table, where: 'source = ?', whereArgs: [source]);
      }
    });
    for (final entry in _ruleToSource.entries) {
      await _deleteOrphanRules(entry.key, entry.value);
    }
  }

  /// Sets `enabled` on all source rows of [source]; the shared rule row keeps its own flag.
  Future<void> setSourceEnabled(String source, bool enabled) async {
    final value = enabled ? 1 : 0;
    await _db.transaction((txn) async {
      for (final table in _sourceTables) {
        await txn.update(
          table,
          {'enabled': value},
          where: 'source = ?',
          whereArgs: [source],
        );
      }
    });
  }

  /// Drops rule rows that no source references; they would only inflate counts.
  ///
  /// Each page is its own transaction, so the write lock is never held longer than one page's
  /// worth of deletes, and the loop yields so queued reads still get a turn.
  Future<void> _deleteOrphanRules(String ruleTable, String sourceTable) async {
    while (true) {
      final removed = await _db.transaction<int>((txn) async {
        final rows = await txn.rawQuery(
          'SELECT id FROM $ruleTable WHERE NOT EXISTS '
          '(SELECT 1 FROM $sourceTable s WHERE s.ruleId = $ruleTable.id) '
          'ORDER BY id LIMIT $orphanPageSize',
        );
        if (rows.isEmpty) return 0;
        final ids = [for (final row in rows) row['id'] as int];
        final placeholders = List.filled(ids.length, '?').join(',');
        await txn.rawDelete(
          'DELETE FROM $ruleTable WHERE id IN ($placeholders)',
          ids,
        );
        return ids.length;
      });
      if (removed == 0) return;
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<int> _insertBlockRules(
    List<ParsedRule> rules, {
    required String source,
    required bool enabled,
  }) => _insertDomainRules(
    rules,
    table: 'block_rule',
    sourceTable: 'block_rule_source',
    source: source,
    enabled: enabled,
  );

  Future<int> _insertAllowRules(
    List<ParsedRule> rules, {
    required String source,
    required bool enabled,
  }) => _insertDomainRules(
    rules,
    table: 'allow_rule',
    sourceTable: 'allow_rule_source',
    source: source,
    enabled: enabled,
  );

  Future<int> _insertDomainRules(
    List<ParsedRule> rules, {
    required String table,
    required String sourceTable,
    required String source,
    required bool enabled,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _writeBatched(rules.length, (batch, index) {
      final rule = rules[index];
      final key = _domainRuleKey(rule);
      batch.rawInsert(
        // Conditional insert, not `INSERT OR IGNORE`: legacy databases have no unique index on
        // the rule table, so dedupe has to be explicit (the SELECT sees rows written earlier in
        // the same batch).
        'INSERT INTO $table '
        '(pattern, rawLine, addedAt, enabled, groupName, important, appScope, appInverted, '
        'isWildcard, denyallow, isRegex, dnsType) '
        'SELECT ?, ?, ?, 1, NULL, ?, ?, ?, ?, ?, ?, ? '
        'WHERE NOT EXISTS (SELECT 1 FROM $table WHERE ${key.where})',
        [
          rule.pattern,
          rule.rawLine,
          now,
          rule.important ? 1 : 0,
          rule.appScope,
          rule.appInverted ? 1 : 0,
          rule.isWildcard ? 1 : 0,
          rule.denyallow,
          rule.isRegex ? 1 : 0,
          rule.dnsType,
          ...key.args,
        ],
      );
      // Same statement finds the row whether it was just inserted or already existed.
      batch.rawInsert(
        'INSERT OR IGNORE INTO $sourceTable (ruleId, source, enabled) '
        'SELECT id, ?, ? FROM $table WHERE ${key.where} ORDER BY id LIMIT 1',
        [source, enabled ? 1 : 0, ...key.args],
      );
    });
  }

  /// Unique-key predicate of a domain rule, mirroring the legacy unique index.
  ///
  /// sqflite warns about `IS ?` with null (and will throw later), so nullable columns use `= ?`
  /// when set and `IS NULL` otherwise.
  ({String where, List<Object?> args}) _domainRuleKey(ParsedRule rule) {
    final where = <String>['pattern = ?', 'important = ?'];
    final args = <Object?>[rule.pattern, rule.important ? 1 : 0];
    final appScope = rule.appScope;
    if (appScope == null) {
      where.add('appScope IS NULL');
    } else {
      where.add('appScope = ?');
      args.add(appScope);
    }
    where.add('appInverted = ?');
    args.add(rule.appInverted ? 1 : 0);
    final dnsType = rule.dnsType;
    if (dnsType == null) {
      where.add('dnsType IS NULL');
    } else {
      where.add('dnsType = ?');
      args.add(dnsType);
    }
    where.add('isRegex = ?');
    args.add(rule.isRegex ? 1 : 0);
    return (where: where.join(' AND '), args: args);
  }

  /// Runs [addRule] for every index inside one transaction, with all statements queued in a single
  /// batch: three statements per rule in one platform round trip instead of three round trips per
  /// rule, which is what made a 1000-rule chunk take seconds and hold the write lock meanwhile.
  ///
  /// [addRule] must add the rule insert and its source insert; the helper appends `SELECT changes()`
  /// so the returned count is the number of source rows actually written.
  Future<int> _writeBatched(
    int count,
    void Function(Batch batch, int index) addRule,
  ) async {
    if (count == 0) return 0;
    var inserted = 0;
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (var index = 0; index < count; index++) {
        addRule(batch, index);
        batch.rawQuery('SELECT changes() AS c');
      }
      final results = await batch.commit(noResult: false);
      for (var index = 2; index < results.length; index += 3) {
        final rows = results[index];
        if (rows is List && rows.isNotEmpty) {
          inserted += (rows.first as Map)['c'] as int? ?? 0;
        }
      }
    });
    return inserted;
  }

  Future<int> _insertRewriteRules(
    List<ParsedRewriteRule> rules, {
    required String source,
    required bool enabled,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _writeBatched(rules.length, (batch, index) {
      final rule = rules[index];
      batch.rawInsert(
        'INSERT INTO rewrite_rule '
        '(pattern, targetType, targetValue, rawLine, addedAt, enabled) '
        'SELECT ?, ?, ?, ?, ?, 1 '
        'WHERE NOT EXISTS (SELECT 1 FROM rewrite_rule '
        'WHERE pattern = ? AND targetType = ? AND targetValue = ?)',
        [
          rule.pattern,
          rule.targetType,
          rule.targetValue,
          rule.rawLine,
          now,
          rule.pattern,
          rule.targetType,
          rule.targetValue,
        ],
      );
      batch.rawInsert(
        'INSERT OR IGNORE INTO rewrite_rule_source (ruleId, source, enabled) '
        'SELECT id, ?, ? FROM rewrite_rule '
        'WHERE pattern = ? AND targetType = ? AND targetValue = ? ORDER BY id LIMIT 1',
        [source, enabled ? 1 : 0, rule.pattern, rule.targetType, rule.targetValue],
      );
    });
  }

  /// URL and path rules go to `go_url_rule`, which has no `appScope` column, so a `$app=` rule is
  /// skipped rather than stored as a global block.
  Future<int> _insertUrlRules(
    List<ParsedUrlRule> rules, {
    required String source,
    required bool enabled,
  }) {
    final kept = [
      for (final rule in rules)
        if (rule.appScope == null || rule.appScope!.isEmpty) rule,
    ];
    final now = DateTime.now().millisecondsSinceEpoch;
    return _writeBatched(kept.length, (batch, index) {
      final rule = kept[index];
      final kind = rule.isAllow ? 'allow' : 'block';
      batch.rawInsert(
        'INSERT INTO go_url_rule (pattern, kind, rawLine, addedAt, enabled) '
        'SELECT ?, ?, ?, ?, 1 '
        'WHERE NOT EXISTS (SELECT 1 FROM go_url_rule WHERE pattern = ? AND kind = ?)',
        [rule.pattern, kind, rule.rawLine, now, rule.pattern, kind],
      );
      batch.rawInsert(
        'INSERT OR IGNORE INTO go_url_rule_source (ruleId, source, enabled) '
        'SELECT id, ?, ? FROM go_url_rule WHERE pattern = ? AND kind = ? ORDER BY id LIMIT 1',
        [source, enabled ? 1 : 0, rule.pattern, kind],
      );
    });
  }

  /// Source tables of every rule family, in the order the sweep expects.
  static const _sourceTables = [
    'block_rule_source',
    'allow_rule_source',
    'rewrite_rule_source',
    'go_url_rule_source',
  ];

  /// rule table -> source table, for the orphan sweep.
  static const _ruleToSource = {
    'block_rule': 'block_rule_source',
    'allow_rule': 'allow_rule_source',
    'rewrite_rule': 'rewrite_rule_source',
    'go_url_rule': 'go_url_rule_source',
  };

  /// Rows per orphan-delete transaction; small enough that the write lock is released often.
  static const orphanPageSize = 2000;
}
