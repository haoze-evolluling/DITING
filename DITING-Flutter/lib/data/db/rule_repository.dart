/// Read/write access to the legacy rule tables; `*_source` join tables carry provenance (`preset`,
/// `useradd`, `sub_<id>`) and a rule applies only when it and one of its sources are enabled.
library;

import 'dart:io';

import 'package:diting/data/mock_data.dart';
import 'package:sqflite/sqflite.dart';

part 'rule_repository_app_scope.dart';

class RuleRepository {
  RuleRepository(this._db, {this.sourceFile});

  final Database _db;

  /// Legacy database file this handle was opened from; null for ad-hoc handles (tests, cleanup).
  final String? sourceFile;

  static const _ruleTables = {
    RuleKind.block: 'block_rule',
    RuleKind.allow: 'allow_rule',
    RuleKind.rewrite: 'rewrite_rule',
  };

  static const _sourceTables = {
    RuleKind.block: 'block_rule_source',
    RuleKind.allow: 'allow_rule_source',
    RuleKind.rewrite: 'rewrite_rule_source',
  };

  /// Sources that [clearUser] may delete; `preset` and `sub_*` are kept.
  static const userSources = ['useradd', 'local_import', 'local_hosts'];

  /// Rows per [loadAllPaged] page: 100k rules is ~125 queries, and one page never dominates the
  /// heap.
  static const loadPageSize = 800;

  Future<Map<RuleKind, List<MockRule>>> loadAll() async {
    final subscriptions = await _subscriptionNames();
    return {
      for (final kind in RuleKind.values)
        kind: await _loadKind(kind, subscriptions),
    };
  }

  Future<List<MockRule>> loadKind(RuleKind kind) async =>
      _loadKind(kind, await _subscriptionNames());

  /// Full-table load in `id` pages, one [onPage] call per page.
  ///
  /// [loadAll] has to hold a whole table and every parsed rule at once; on a subscription-sized
  /// dataset that is what pushed the heap to its 256MB limit during startup. Paging keeps the peak
  /// at one page and lets the caller publish each page as it arrives.
  Future<void> loadAllPaged(
    void Function(RuleKind kind, List<MockRule> page) onPage, {
    int pageSize = loadPageSize,
  }) async {
    final subscriptions = await _subscriptionNames();
    for (final kind in RuleKind.values) {
      int? beforeId;
      while (true) {
        final page = await _loadKindPage(
          kind,
          subscriptions,
          beforeId: beforeId,
          limit: pageSize,
        );
        if (page.isEmpty) break;
        onPage(kind, page);
        if (page.length < pageSize) break;
        beforeId = int.parse(page.last.id);
      }
    }
  }

  Future<Map<int, String>> _subscriptionNames() async {
    final rows = await _db.query('subscription', columns: ['id', 'name']);
    return {for (final row in rows) row['id'] as int: row['name'] as String};
  }

  Future<List<MockRule>> _loadKind(
    RuleKind kind,
    Map<int, String> subscriptionNames,
  ) => _loadKindPage(kind, subscriptionNames);

  /// One `id` range of a rule table, or the whole table when [limit] is null.
  ///
  /// The `*_source` rows are joined in rather than fetched as their own full table: the two reads
  /// used to exist side by side, so this halves the peak for the same result. [beforeId] is
  /// exclusive and pages walk `id DESC`, which keeps a rule's sources inside one page.
  Future<List<MockRule>> _loadKindPage(
    RuleKind kind,
    Map<int, String> subscriptionNames, {
    int? beforeId,
    int? limit,
  }) async {
    final table = _ruleTables[kind]!;
    final sources = _sourceTables[kind]!;
    final rows = await _db.rawQuery(
      'SELECT r.*, s.source AS sourceName, s.enabled AS sourceEnabled FROM '
      '(SELECT * FROM $table'
      '${beforeId == null ? '' : ' WHERE id < ?'} ORDER BY id DESC'
      '${limit == null ? '' : ' LIMIT ?'}) r '
      'LEFT JOIN $sources s ON s.ruleId = r.id '
      'ORDER BY r.id DESC',
      [?beforeId, ?limit],
    );
    return _rowsToRules(kind, rows, subscriptionNames);
  }

  /// Groups the joined rows back into rules; consecutive rows share an `id` because of the
  /// `ORDER BY r.id DESC`.
  List<MockRule> _rowsToRules(
    RuleKind kind,
    List<Map<String, Object?>> rows,
    Map<int, String> subscriptionNames,
  ) {
    final rules = <MockRule>[];
    var index = 0;
    while (index < rows.length) {
      final row = rows[index];
      final id = row['id'] as int;
      final sources = <_SourceRef>[];
      while (index < rows.length && rows[index]['id'] == id) {
        final source = rows[index]['sourceName'] as String?;
        if (source != null) {
          sources.add(
            _SourceRef(source, (rows[index]['sourceEnabled'] as int? ?? 0) == 1),
          );
        }
        index++;
      }
      rules.add(_toRule(kind, row, sources, subscriptionNames));
    }
    return rules;
  }

  MockRule _toRule(
    RuleKind kind,
    Map<String, Object?> row,
    List<_SourceRef> sources,
    Map<int, String> subscriptionNames,
  ) {
    final sourceEnabled = sources.isEmpty || sources.any((ref) => ref.enabled);
    final appScope = (row['appScope'] as String?)?.trim();
    return MockRule(
      id: '${row['id']}',
      pattern: row['pattern'] as String,
      kind: kind,
      source: _originOf(sources),
      enabled: (row['enabled'] as int) == 1 && sourceEnabled,
      important:
          kind != RuleKind.rewrite && (row['important'] as int? ?? 0) == 1,
      group: row['groupName'] as String?,
      subscriptionName: _subscriptionNameOf(sources, subscriptionNames),
      target: kind == RuleKind.rewrite ? row['targetValue'] as String? : null,
      appScope: appScope == null || appScope.isEmpty ? null : appScope,
      appInverted:
          kind != RuleKind.rewrite && (row['appInverted'] as int? ?? 0) == 1,
    );
  }

  RuleSource _originOf(List<_SourceRef> sources) {
    if (sources.any((ref) => ref.source == 'preset')) {
      return RuleSource.preset;
    }
    if (sources.any((ref) => ref.source.startsWith('sub_'))) {
      return RuleSource.subscription;
    }
    return RuleSource.user;
  }

  String? _subscriptionNameOf(
    List<_SourceRef> sources,
    Map<int, String> names,
  ) {
    for (final ref in sources) {
      if (!ref.source.startsWith('sub_')) {
        continue;
      }
      final id = int.tryParse(ref.source.substring(4));
      if (id != null && names.containsKey(id)) {
        return names[id];
      }
    }
    return null;
  }

  /// Inserts a user rule and its `useradd` source, reusing a row with the same identity.
  Future<MockRule> add(RuleKind kind, String pattern, {String? target}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await _db.transaction<int>((txn) async {
      final existing = await _findExisting(txn, kind, pattern, target);
      final ruleId =
          existing ?? await _insertRule(txn, kind, pattern, target, now);
      await txn.insert(_sourceTables[kind]!, {
        'ruleId': ruleId,
        'source': 'useradd',
        'enabled': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return ruleId;
    });
    return MockRule(
      id: '$id',
      pattern: pattern,
      kind: kind,
      source: RuleSource.user,
      target: target,
    );
  }

  Future<int?> _findExisting(
    DatabaseExecutor txn,
    RuleKind kind,
    String pattern,
    String? target,
  ) async {
    final rows = kind == RuleKind.rewrite
        ? await txn.query(
            'rewrite_rule',
            columns: ['id'],
            where: 'pattern = ? AND targetType = ? AND targetValue = ?',
            whereArgs: [pattern, rewriteTargetType(target), target],
            limit: 1,
          )
        : await txn.query(
            _ruleTables[kind]!,
            columns: ['id'],
            where:
                'pattern = ? AND important = 0 AND appScope IS NULL '
                'AND appInverted = 0 AND dnsType IS NULL AND isRegex = 0',
            whereArgs: [pattern],
            limit: 1,
          );
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  Future<int> _insertRule(
    DatabaseExecutor txn,
    RuleKind kind,
    String pattern,
    String? target,
    int addedAt, {
    String? groupName,
  }) {
    if (kind == RuleKind.rewrite) {
      return txn.insert('rewrite_rule', {
        'pattern': pattern,
        'targetType': rewriteTargetType(target),
        'targetValue': target,
        'rawLine': pattern,
        'addedAt': addedAt,
        'enabled': 1,
      });
    }
    return txn.insert(_ruleTables[kind]!, {
      'pattern': pattern,
      'rawLine': pattern,
      'addedAt': addedAt,
      'enabled': 1,
      'groupName': groupName,
      'important': 0,
      'appScope': null,
      'appInverted': 0,
      'isWildcard': pattern.contains('*') ? 1 : 0,
      'denyallow': null,
      'isRegex': 0,
      'dnsType': null,
    });
  }

  Future<void> setEnabled(RuleKind kind, int id, bool enabled) => _db.update(
    _ruleTables[kind]!,
    {'enabled': enabled ? 1 : 0},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// [promotePreset] turns a preset rule into a user rule, so a preset reset cannot revert the
  /// edit.
  Future<void> update(
    RuleKind kind,
    int id,
    String pattern, {
    String? target,
    bool promotePreset = false,
  }) async {
    await _db.transaction((txn) async {
      if (kind == RuleKind.rewrite) {
        await txn.update(
          'rewrite_rule',
          {
            'pattern': pattern,
            'targetType': rewriteTargetType(target),
            'targetValue': target,
            'rawLine': pattern,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      } else {
        await txn.update(
          _ruleTables[kind]!,
          {'pattern': pattern, 'rawLine': pattern},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      if (promotePreset) {
        final sources = _sourceTables[kind]!;
        await txn.delete(
          sources,
          where: 'ruleId = ? AND source = ?',
          whereArgs: [id, 'preset'],
        );
        await txn.insert(sources, {
          'ruleId': id,
          'source': 'useradd',
          'enabled': 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> delete(RuleKind kind, int id) =>
      _db.delete(_ruleTables[kind]!, where: 'id = ?', whereArgs: [id]);

  /// Removes user-owned sources and any rules left without a source.
  Future<int> clearUser(RuleKind kind) async {
    final table = _ruleTables[kind]!;
    final sources = _sourceTables[kind]!;
    return _db.transaction<int>((txn) async {
      final placeholders = List.filled(userSources.length, '?').join(',');
      final affected = await txn.rawQuery(
        'SELECT DISTINCT ruleId FROM $sources WHERE source IN ($placeholders)',
        userSources,
      );
      await txn.delete(
        sources,
        where: 'source IN ($placeholders)',
        whereArgs: userSources,
      );
      await txn.delete(
        table,
        where:
            'NOT EXISTS (SELECT 1 FROM $sources s WHERE s.ruleId = $table.id)',
      );
      return affected.length;
    });
  }

  /// How many user-origin rules exist across the three kinds, counted inside SQLite.
  ///
  /// The backup overview only needs the number: loading the tables through [loadKind] to count
  /// them in Dart allocated the whole dataset on subscription-sized databases, which is what
  /// crashed the config export.
  Future<int> countUser() async {
    final placeholders = List.filled(userSources.length, '?').join(',');
    var total = 0;
    for (final kind in RuleKind.values) {
      final rows = await _db.rawQuery(
        'SELECT COUNT(DISTINCT r.id) AS n FROM ${_ruleTables[kind]} r '
        'JOIN ${_sourceTables[kind]} s ON s.ruleId = r.id '
        'WHERE s.source IN ($placeholders)',
        userSources,
      );
      total += (rows.first['n'] as num?)?.toInt() ?? 0;
    }
    return total;
  }

  Future<int> resetPresetWhitelist(
    List<({String domain, String group})> entries,
  ) {
    return _db.transaction<int>((txn) async {
      await txn.delete(
        'allow_rule_source',
        where: 'source = ?',
        whereArgs: ['preset'],
      );
      await txn.delete(
        'allow_rule',
        where:
            'NOT EXISTS (SELECT 1 FROM allow_rule_source s '
            'WHERE s.ruleId = allow_rule.id)',
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final entry in entries) {
        final id = await _insertRule(
          txn,
          RuleKind.allow,
          entry.domain,
          null,
          now,
          groupName: entry.group,
        );
        await txn.insert('allow_rule_source', {
          'ruleId': id,
          'source': 'preset',
          'enabled': 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      return entries.length;
    });
  }

}

String rewriteTargetType(String? target) {
  if (target == null || target.isEmpty) {
    return 'CNAME';
  }
  final address = InternetAddress.tryParse(target);
  if (address == null) {
    return 'CNAME';
  }
  return address.type == InternetAddressType.IPv4 ? 'IPv4' : 'IPv6';
}

class _SourceRef {
  const _SourceRef(this.source, this.enabled);

  final String source;
  final bool enabled;
}
