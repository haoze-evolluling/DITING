/// Read/write access to the legacy rule tables; `*_source` join tables carry provenance (`preset`,
/// `useradd`, `sub_<id>`) and a rule applies only when it and one of its sources are enabled.
///
/// Every predicate, table name and row mapping comes from `rust/diting-rule-store-core`; this file
/// runs the statements inside `sqflite` transactions and nothing else.
library;

import 'package:diting_android/data/db/rust_rule_store_core.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:sqflite/sqflite.dart';

part 'rule_repository_app_scope.dart';

class RuleRepository {
  RuleRepository(this._db, {this.sourceFile});

  final Database _db;

  /// Legacy database file this handle was opened from; null for ad-hoc handles (tests, cleanup).
  final String? sourceFile;

  /// Table pair per kind, read from the core so the names exist in exactly one place.
  static final Map<RuleKind, ({String table, String sourceTable})> _tables =
      _tablesFromCore();

  /// Sources that [clearUser] may delete; `preset` and `sub_*` are kept.
  static final List<String> userSources = _userSourcesFromCore();

  /// Rows per [loadAllPaged] page: 100k rules is ~125 queries, and one page never dominates the
  /// heap.
  static const loadPageSize = 800;

  static ({Map<RuleKind, ({String table, String sourceTable})> tables, List<String> userSources})
  _coreTables() {
    final answer = RustRuleStoreCore.instance.plan({'op': 'tables'});
    ({String table, String sourceTable}) pair(String key) {
      final record = (answer[key] as Map?) ?? const {};
      return (
        table: '${record['table']}',
        sourceTable: '${record['sourceTable']}',
      );
    }

    final sources = [
      for (final source in answer['userSources'] as List? ?? const []) '$source',
    ];
    return (
      tables: {
        RuleKind.block: pair('block'),
        RuleKind.allow: pair('allow'),
        RuleKind.rewrite: pair('rewrite'),
      },
      userSources: sources,
    );
  }

  static Map<RuleKind, ({String table, String sourceTable})> _tablesFromCore() =>
      _coreTables().tables;

  static List<String> _userSourcesFromCore() => _coreTables().userSources;

  static String _kindKey(RuleKind kind) => switch (kind) {
    RuleKind.block => 'block',
    RuleKind.allow => 'allow',
    RuleKind.rewrite => 'rewrite',
  };

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
  /// used to exist side by side, so this halves the peak for the same result.
  Future<List<MockRule>> _loadKindPage(
    RuleKind kind,
    Map<int, String> subscriptionNames, {
    int? beforeId,
    int? limit,
  }) async {
    final query = RustRuleStoreCore.instance.plan({
      'op': 'pageQuery',
      'kind': _kindKey(kind),
      'beforeId': ?beforeId,
      'limit': ?limit,
    });
    final rows = await _db.rawQuery(
      '${query['sql']}',
      sqlArgs(query['args']),
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
    final mapped = RustRuleStoreCore.instance.rows(
      kind: _kindKey(kind),
      subscriptions: subscriptionNames,
      joined: rows,
    );
    return [for (final rule in mapped) _toRule(kind, rule)];
  }

  static MockRule _toRule(RuleKind kind, Map<String, Object?> rule) => MockRule(
    id: '${rule['id']}',
    pattern: '${rule['pattern']}',
    kind: kind,
    source: switch ('${rule['source']}') {
      'preset' => RuleSource.preset,
      'subscription' => RuleSource.subscription,
      _ => RuleSource.user,
    },
    enabled: rule['enabled'] == true,
    important: rule['important'] == true,
    group: rule['group'] as String?,
    subscriptionName: rule['subscriptionName'] as String?,
    target: rule['target'] as String?,
    appScope: rule['appScope'] as String?,
    appInverted: rule['appInverted'] == true,
  );

  /// One rule's identity: the predicate that finds it and the row a new one is written with.
  static Map<String, Object?> _identity(
    RuleKind kind, {
    String flavor = 'global',
    Map<String, Object?> rule = const {},
    String? package,
    required int now,
  }) => RustRuleStoreCore.instance.plan({
    'op': 'identity',
    'kind': _kindKey(kind),
    'flavor': flavor,
    'rule': rule,
    'nowMs': now,
    'package': ?package,
  });

  static String _where(Map<String, Object?> identity) => '${identity['where']}';

  static List<Object?> _args(Map<String, Object?> identity) =>
      sqlArgs(identity['args']);

  static Map<String, Object?> _row(Map<String, Object?> identity) =>
      ((identity['row'] as Map?) ?? const {}).cast<String, Object?>();

  /// Inserts a user rule and its `useradd` source, reusing a row with the same identity.
  Future<MockRule> add(RuleKind kind, String pattern, {String? target}) async {
    final tables = _tables[kind]!;
    final identity = _identity(
      kind,
      rule: {'pattern': pattern, 'target': target},
      now: DateTime.now().millisecondsSinceEpoch,
    );
    final row = _row(identity);
    final id = await _db.transaction<int>((txn) async {
      final existing = await txn.query(
        tables.table,
        columns: ['id'],
        where: _where(identity),
        whereArgs: _args(identity),
        limit: 1,
      );
      final ruleId = existing.isEmpty
          ? await txn.insert(tables.table, row)
          : existing.first['id'] as int;
      await txn.insert(tables.sourceTable, {
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

  Future<void> setEnabled(RuleKind kind, int id, bool enabled) => _db.update(
    _tables[kind]!.table,
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
    final tables = _tables[kind]!;
    final row = _row(
      _identity(
        kind,
        rule: {'pattern': pattern, 'target': target},
        now: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _db.transaction((txn) async {
      if (kind == RuleKind.rewrite) {
        await txn.update(
          tables.table,
          {
            'pattern': pattern,
            'targetType': row['targetType'],
            'targetValue': row['targetValue'],
            'rawLine': row['rawLine'],
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      } else {
        await txn.update(
          tables.table,
          {'pattern': pattern, 'rawLine': row['rawLine']},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      if (promotePreset) {
        await txn.delete(
          tables.sourceTable,
          where: 'ruleId = ? AND source = ?',
          whereArgs: [id, 'preset'],
        );
        await txn.insert(tables.sourceTable, {
          'ruleId': id,
          'source': 'useradd',
          'enabled': 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> delete(RuleKind kind, int id) => _db.delete(
    _tables[kind]!.table,
    where: 'id = ?',
    whereArgs: [id],
  );

  /// Removes user-owned sources and any rules left without a source.
  Future<int> clearUser(RuleKind kind) async {
    final tables = _tables[kind]!;
    return _db.transaction<int>((txn) async {
      final placeholders = List.filled(userSources.length, '?').join(',');
      final affected = await txn.rawQuery(
        'SELECT DISTINCT ruleId FROM ${tables.sourceTable} '
        'WHERE source IN ($placeholders)',
        userSources,
      );
      await txn.delete(
        tables.sourceTable,
        where: 'source IN ($placeholders)',
        whereArgs: userSources,
      );
      await txn.delete(
        tables.table,
        where:
            'NOT EXISTS (SELECT 1 FROM ${tables.sourceTable} s '
            'WHERE s.ruleId = ${tables.table}.id)',
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
      final tables = _tables[kind]!;
      final rows = await _db.rawQuery(
        'SELECT COUNT(DISTINCT r.id) AS n FROM ${tables.table} r '
        'JOIN ${tables.sourceTable} s ON s.ruleId = r.id '
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
    final tables = _tables[RuleKind.allow]!;
    return _db.transaction<int>((txn) async {
      await txn.delete(
        tables.sourceTable,
        where: 'source = ?',
        whereArgs: ['preset'],
      );
      await txn.delete(
        tables.table,
        where:
            'NOT EXISTS (SELECT 1 FROM ${tables.sourceTable} s '
            'WHERE s.ruleId = ${tables.table}.id)',
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final entry in entries) {
        final row = _row(
          _identity(
            RuleKind.allow,
            rule: {'pattern': entry.domain, 'group': entry.group},
            now: now,
          ),
        );
        final id = await txn.insert(tables.table, row);
        await txn.insert(tables.sourceTable, {
          'ruleId': id,
          'source': 'preset',
          'enabled': 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      return entries.length;
    });
  }
}
