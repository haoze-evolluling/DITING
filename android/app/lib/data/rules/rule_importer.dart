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

  int get insertedCount =>
      blockCount + allowCount + rewriteCount + urlBlockCount + urlAllowCount;

  int get notAppliedCount => cosmeticCount;

  bool get isEmpty => insertedCount == 0;

  RuleImportSummary merge(RuleImportSummary other) => RuleImportSummary(
    blockCount: blockCount + other.blockCount,
    allowCount: allowCount + other.allowCount,
    rewriteCount: rewriteCount + other.rewriteCount,
    urlBlockCount: urlBlockCount + other.urlBlockCount,
    urlAllowCount: urlAllowCount + other.urlAllowCount,
    cosmeticCount: cosmeticCount + other.cosmeticCount,
    duplicateCount: duplicateCount + other.duplicateCount,
    invalidCount: invalidCount + other.invalidCount,
    unsupportedCount: unsupportedCount + other.unsupportedCount,
    typeSkippedCount: typeSkippedCount + other.typeSkippedCount,
    badfilteredCount: badfilteredCount + other.badfilteredCount,
  );
}

String subscriptionSourceTag(int subscriptionId) => 'sub_$subscriptionId';

class RuleImporter {
  RuleImporter(this._db, {this.chunkSize = 1000});

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

  Future<RuleImportSummary> import(
    CategorizedRules parsed, {
    required String source,
    required String kind,
    required bool enabled,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final domainOnly = kind != 'hosts';
    final counts = <String, int>{};

    Future<void> runFamily<P>(
      String family,
      String familyKey,
      List<P> rules,
      Map<String, Object?> Function(P) toJson, {
      bool Function(P)? keep,
    }) async {
      for (var start = 0; start < rules.length; start += chunkSize) {
        final end = start + chunkSize < rules.length ? start + chunkSize : rules.length;
        final chunk = <Map<String, Object?>>[
          for (var i = start; i < end; i++)
            if (keep == null || keep(rules[i])) toJson(rules[i]),
        ];
        if (chunk.isEmpty) continue;
        final plan = RustRuleStoreCore.instance.plan({
          'op': 'import',
          'source': source,
          'kind': kind,
          'enabled': enabled,
          'chunkSize': chunkSize,
          'nowMs': now,
          'parsed': {familyKey: chunk},
        });
        for (final batch in plan['batches'] as List? ?? const []) {
          if (batch is! Map) continue;
          counts[family] =
              (counts[family] ?? 0) + await _runBatch(batch['steps'] as List? ?? const []);
        }
      }
    }

    await runFamily('block', 'blockRules', parsed.blockRules, _ruleJson);
    if (domainOnly) {
      await runFamily('allow', 'allowRules', parsed.allowRules, _ruleJson);
    }
    await runFamily('rewrite', 'rewriteRules', parsed.rewriteRules, _rewriteJson);
    if (domainOnly) {
      await runFamily(
        'urlBlock',
        'urlBlockRules',
        parsed.urlBlockRules,
        _urlJson,
        keep: _keepUrlRule,
      );
      await runFamily(
        'urlAllow',
        'urlAllowRules',
        parsed.urlAllowRules,
        _urlJson,
        keep: _keepUrlRule,
      );
    }

    return RuleImportSummary(
      blockCount: counts['block'] ?? 0,
      allowCount: counts['allow'] ?? 0,
      rewriteCount: counts['rewrite'] ?? 0,
      urlBlockCount: counts['urlBlock'] ?? 0,
      urlAllowCount: counts['urlAllow'] ?? 0,
      cosmeticCount: domainOnly ? parsed.cosmeticRules.length : 0,
      duplicateCount: parsed.duplicateCount,
      invalidCount: parsed.invalidCount,
      unsupportedCount: parsed.unsupportedCount,
      typeSkippedCount: domainOnly
          ? 0
          : parsed.allowRules.length +
                parsed.urlBlockRules.length +
                parsed.urlAllowRules.length,
      badfilteredCount: parsed.badfilteredCount,
    );
  }

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

  static Map<String, Object?> _rewriteJson(ParsedRewriteRule rule) => {
    'pattern': rule.pattern,
    'targetType': rule.targetType,
    'targetValue': rule.targetValue,
    'rawLine': rule.rawLine,
  };

  static bool _keepUrlRule(ParsedUrlRule rule) {
    final scope = rule.appScope;
    return scope == null || scope.trim().isEmpty;
  }

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
