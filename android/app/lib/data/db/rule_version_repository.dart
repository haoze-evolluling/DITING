library;

import 'dart:convert';

import 'package:diting_android/data/rules/rule_models.dart';
import 'package:diting_android/data/rules/rust_rule_version_core.dart';
import 'package:sqflite/sqflite.dart';

List<String> canonicalRules(CategorizedRules parsed) => [
  for (final rule in parsed.blockRules) rule.rawLine,
  for (final rule in parsed.allowRules) rule.rawLine,
  for (final rule in parsed.rewriteRules) rule.rawLine,
  for (final rule in parsed.urlBlockRules) rule.rawLine,
  for (final rule in parsed.urlAllowRules) rule.rawLine,
];

class StoredRuleVersion {
  const StoredRuleVersion({
    required this.id,
    required this.hash,
    required this.ruleCount,
    required this.createdAt,
    required this.rules,
  });

  final int id;
  final String hash;
  final int ruleCount;
  final int createdAt;
  final List<String> rules;
}

const int _ruleSetHashSeed = 0x811c9dc5;
const int _ruleSetHashPrime = 0x01000193;

int ruleSetHashSeed() => _ruleSetHashSeed;

int ruleSetHashUpdate(int hash, Iterable<String> rules) {
  var state = hash;
  for (final rule in rules) {
    for (final unit in rule.codeUnits) {
      state ^= unit;
      state = (state * _ruleSetHashPrime) & 0xffffffff;
    }
    state ^= 0x0a;
    state = (state * _ruleSetHashPrime) & 0xffffffff;
  }
  return state;
}

String ruleSetHashHex(int hash) => hash.toRadixString(16).padLeft(8, '0');

String ruleSetHash(List<String> rules) =>
    ruleSetHashHex(ruleSetHashUpdate(ruleSetHashSeed(), rules));

class RuleVersionRepository {
  RuleVersionRepository(this._db);

  final Database _db;

  Future<void> ensureTable() async {
    await _db.execute(
      'CREATE TABLE IF NOT EXISTS rule_version ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'group_id TEXT NOT NULL, '
      'hash TEXT NOT NULL, '
      'rule_count INTEGER NOT NULL, '
      'created_at INTEGER NOT NULL, '
      'rules_json TEXT NOT NULL)',
    );
    await _db.execute(
      'CREATE INDEX IF NOT EXISTS index_rule_version_group '
      'ON rule_version (group_id, created_at DESC)',
    );
  }

  Future<List<StoredRuleVersion>> history(String groupId, {int limit = 10}) async {
    await ensureTable();
    final rows = await _db.query(
      'rule_version',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return [for (final row in rows) _fromRow(row)];
  }

  Future<StoredRuleVersion?> latest(String groupId) async {
    final rows = await history(groupId, limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> recordVersion({
    required String groupId,
    required String hash,
    required int ruleCount,
    required List<String> rules,
    int? max,
  }) async {
    await ensureTable();
    final existing = await history(groupId, limit: 50);
    final entries = [
      for (final version in existing)
        RuleVersionEntry(
          hash: version.hash,
          ruleCount: version.ruleCount,
          createdAt: version.createdAt,
        ),
    ];
    final next = RustRuleVersionCore.instance.record(
      entries,
      hash: hash,
      ruleCount: ruleCount,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      max: max,
    );
    if (existing.isNotEmpty && next.isNotEmpty && next.first.hash == existing.first.hash) {
      return;
    }
    final head = next.first;
    final alreadyStored = existing.any(
      (version) => version.hash == head.hash && version.createdAt == head.createdAt,
    );
    if (!alreadyStored) {
      await _db.insert('rule_version', {
        'group_id': groupId,
        'hash': head.hash,
        'rule_count': head.ruleCount,
        'created_at': head.createdAt,
        'rules_json': jsonEncode(rules),
      });
    }
    final kept = {for (final entry in next) '${entry.hash}@${entry.createdAt}'};
    final all = await _db.query(
      'rule_version',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'created_at DESC, id DESC',
    );
    for (final row in all) {
      final key = '${row['hash']}@${row['created_at']}';
      if (!kept.contains(key)) {
        await _db.delete('rule_version', where: 'id = ?', whereArgs: [row['id']]);
      }
    }
  }

  StoredRuleVersion _fromRow(Map<String, Object?> row) => StoredRuleVersion(
    id: (row['id'] as num?)?.toInt() ?? 0,
    hash: row['hash'] as String? ?? '',
    ruleCount: (row['rule_count'] as num?)?.toInt() ?? 0,
    createdAt: (row['created_at'] as num?)?.toInt() ?? 0,
    rules: _decodeRules(row['rules_json']),
  );

  static List<String> _decodeRules(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [for (final item in decoded) if (item is String) item];
  }
}
