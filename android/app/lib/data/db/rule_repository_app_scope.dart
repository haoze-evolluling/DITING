part of 'rule_repository.dart';

// Per-app rules (`appScope`) and the `*` full-block marker, split out of RuleRepository. Every
// predicate comes from the core: the scope list is `|`-separated, so "does this rule apply to app X"
// is four `LIKE` comparisons that must not be rewritten by hand.

extension RuleRepositoryAppScope on RuleRepository {
  static Map<String, Object?> _predicate(String name, String packageName) =>
      RustRuleStoreCore.instance.plan({
        'op': 'predicate',
        'name': name,
        'package': packageName,
      });

  /// Excludes the `*` full-block marker; sources are read, so all-disabled yields false.
  Future<List<MockRule>> loadForApp(String packageName) async {
    final subscriptions = await _subscriptionNames();
    final scoped = _predicate('loadForApp', packageName);
    final result = <MockRule>[];
    for (final kind in [RuleKind.block, RuleKind.allow]) {
      final tables = RuleRepository._tables[kind]!;
      final rows = await _db.query(
        tables.table,
        where: '${scoped['where']}',
        whereArgs: sqlArgs(scoped['args']),
        orderBy: 'id DESC',
      );
      if (rows.isEmpty) continue;
      final ids = [for (final row in rows) row['id'] as int];
      final placeholders = List.filled(ids.length, '?').join(',');
      final sourceRows = await _db.query(
        tables.sourceTable,
        where: 'ruleId IN ($placeholders)',
        whereArgs: ids,
      );
      final mapped = RustRuleStoreCore.instance.rows(
        kind: RuleRepository._kindKey(kind),
        subscriptions: subscriptions,
        rules: rows,
        sources: sourceRows,
      );
      result.addAll([
        for (final rule in mapped) RuleRepository._toRule(kind, rule),
      ]);
    }
    return result;
  }

  /// Returns the new row, or null when an identical scoped rule already exists; that duplicate is
  /// re-enabled and gets a `useradd` source.
  Future<MockRule?> addForApp(
    RuleKind kind,
    String pattern,
    String packageName, {
    bool important = false,
  }) async {
    if (kind == RuleKind.rewrite) {
      throw ArgumentError('rewrite rules are global only');
    }
    if (pattern.trim().isEmpty || packageName.trim().isEmpty) return null;
    final tables = RuleRepository._tables[kind]!;
    final identity = RuleRepository._identity(
      kind,
      flavor: 'scoped',
      rule: {'pattern': pattern, 'important': important},
      package: packageName,
      now: DateTime.now().millisecondsSinceEpoch,
    );
    final row = RuleRepository._row(identity);
    final outcome = await _db.transaction<int?>((txn) async {
      final existing = await txn.query(
        tables.table,
        columns: ['id'],
        where: RuleRepository._where(identity),
        whereArgs: RuleRepository._args(identity),
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final id = existing.first['id'] as int;
        // Re-enable a disabled duplicate instead of silently no-oping.
        await txn.update(
          tables.table,
          {'enabled': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await txn.insert(tables.sourceTable, {
          'ruleId': id,
          'source': 'useradd',
          'enabled': 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        return null;
      }
      final id = await txn.insert(tables.table, row);
      await txn.insert(tables.sourceTable, {
        'ruleId': id,
        'source': 'useradd',
        'enabled': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return id;
    });
    if (outcome == null) return null;
    return MockRule(
      id: '$outcome',
      pattern: '${row['pattern']}',
      kind: kind,
      source: RuleSource.user,
      important: important,
      appScope: packageName,
    );
  }

  /// Whether the app has the `*` full-block rule (`*$app=<pkg>`).
  Future<bool> hasFullBlock(String packageName) async {
    final predicate = _predicate('fullBlockEnabled', packageName);
    final rows = await _db.query(
      RuleRepository._tables[RuleKind.block]!.table,
      columns: ['id'],
      where: '${predicate['where']}',
      whereArgs: sqlArgs(predicate['args']),
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Enables or removes the app's `pattern = '*'` full-block rule; returns the new state.
  Future<bool> setFullBlock(String packageName, bool enabled) async {
    final tables = RuleRepository._tables[RuleKind.block]!;
    final predicate = _predicate('fullBlock', packageName);
    final existing = await _db.query(
      tables.table,
      columns: ['id'],
      where: '${predicate['where']}',
      whereArgs: sqlArgs(predicate['args']),
      limit: 1,
    );
    final row = RuleRepository._row(
      RuleRepository._identity(
        RuleKind.block,
        flavor: 'fullBlock',
        rule: const {'pattern': '*'},
        package: packageName,
        now: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _db.transaction((txn) async {
      if (enabled) {
        final id = existing.isEmpty
            ? await txn.insert(tables.table, row)
            : existing.first['id'] as int;
        await txn.update(
          tables.table,
          {'enabled': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await txn.insert(tables.sourceTable, {
          'ruleId': id,
          'source': 'useradd',
          'enabled': 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } else if (existing.isNotEmpty) {
        final id = existing.first['id'] as int;
        await txn.delete(tables.table, where: 'id = ?', whereArgs: [id]);
        await txn.delete(
          tables.sourceTable,
          where: 'ruleId = ?',
          whereArgs: [id],
        );
      }
    });
    return enabled;
  }
}
