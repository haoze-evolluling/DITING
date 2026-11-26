library;

import 'package:diting_android/data/db/rust_rule_store_core.dart';
import 'package:diting_android/data/rules/rule_models.dart';
import 'package:diting_android/data/rules/rust_rule_core.dart';
import 'package:diting_android/ui/scroll_activity.dart';
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

/// 导入期间的暂存来源。引擎与规则列表都只认 `sub_*` / 自定义来源，
/// 因此暂存行在原子切换前不会生效。
String subscriptionStagingTag(int subscriptionId) =>
    'staging_sub_$subscriptionId';

class RuleImporter {
  RuleImporter(this._db, {this.chunkSize = ruleStreamChunkLines});

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

    // 每批规则一次 FFI 调用即可拿到全部 family 的 SQL 计划，
    // 避免按 family 反复序列化同一批规则。
    final body = <String, Object?>{
      'blockRules': [for (final rule in parsed.blockRules) _ruleJson(rule)],
      if (domainOnly)
        'allowRules': [for (final rule in parsed.allowRules) _ruleJson(rule)],
      'rewriteRules': [
        for (final rule in parsed.rewriteRules) _rewriteJson(rule),
      ],
      if (domainOnly)
        'urlBlockRules': [
          for (final rule in parsed.urlBlockRules)
            if (_keepUrlRule(rule)) _urlJson(rule),
        ],
      if (domainOnly)
        'urlAllowRules': [
          for (final rule in parsed.urlAllowRules)
            if (_keepUrlRule(rule)) _urlJson(rule),
        ],
    };

    // 分片导入仍会在主 isolate 上做 FFI 解析与写库，逐片让出给滑动帧。
    await ScrollActivityGate.whenIdleAsync();
    final plan = RustRuleStoreCore.instance.plan({
      'op': 'import',
      'source': source,
      'kind': kind,
      'enabled': enabled,
      'chunkSize': chunkSize,
      'nowMs': now,
      'parsed': body,
    });
    counts.addAll(await _runPlan(plan['batches'] as List? ?? const []));

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
        await txn.rawDelete('${step['sql']}', sqlArgs(step['args']));
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
        await txn.rawUpdate('${step['sql']}', sqlArgs(step['args']));
      }
    });
  }

  /// 把暂存来源原子切换到正式来源：同一事务内删除旧关联、
  /// 复制暂存关联并清理暂存行，失败时旧规则原样保留。
  Future<void> commitStaging(
    String staging,
    String source, {
    required bool enabled,
  }) async {
    final plan = RustRuleStoreCore.instance.plan({
      'op': 'commitSource',
      'staging': staging,
      'source': source,
      'enabled': enabled,
    });
    await _db.transaction((txn) async {
      for (final step in plan['steps'] as List? ?? const []) {
        if (step is! Map) continue;
        final sql = '${step['sql']}';
        final args = sqlArgs(step['args']);
        if (sql.startsWith('INSERT')) {
          await txn.rawInsert(sql, args);
        } else if (sql.startsWith('UPDATE') || sql.startsWith('DELETE')) {
          await txn.rawUpdate(sql, args);
        } else {
          await txn.rawQuery(sql, args);
        }
      }
    });
    for (final orphan in plan['orphans'] as List? ?? const []) {
      if (orphan is Map) await _sweepOrphans(orphan);
    }
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

  /// 一个解析分片的所有 family 在同一个事务内写入，减少提交次数；
  /// 任一 family 失败时整片回滚，不会留下半套规则。
  Future<Map<String, int>> _runPlan(List batches) async {
    final counts = <String, int>{};
    if (batches.isEmpty) return counts;
    await _db.transaction((txn) async {
      final batch = txn.batch();
      final counted = <(int, String)>[];
      var index = 0;
      for (final entry in batches) {
        if (entry is! Map) continue;
        final family = '${entry['family']}';
        for (final step in entry['steps'] as List? ?? const []) {
          if (step is! Map) continue;
          final sql = '${step['sql']}';
          final args = sqlArgs(step['args']);
          if (sql.startsWith('INSERT')) {
            batch.rawInsert(sql, args);
          } else if (sql.startsWith('UPDATE') || sql.startsWith('DELETE')) {
            batch.rawUpdate(sql, args);
          } else if (sql.startsWith('CREATE') ||
              sql.startsWith('DROP') ||
              sql.startsWith('ALTER') ||
              sql.startsWith('PRAGMA')) {
            batch.execute(sql, args);
          } else {
            batch.rawQuery(sql, args);
          }
          index++;
          if (step['changes'] == true) {
            batch.rawQuery('SELECT changes() AS c');
            counted.add((index, family));
            index++;
          }
        }
      }
      final results = await batch.commit(noResult: false);
      for (final (position, family) in counted) {
        final rows = results[position];
        if (rows is List && rows.isNotEmpty) {
          counts[family] =
              (counts[family] ?? 0) + ((rows.first as Map)['c'] as int? ?? 0);
        }
      }
    });
    return counts;
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
