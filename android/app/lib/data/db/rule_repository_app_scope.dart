part of 'rule_repository.dart';

// Per-app rules (`appScope`) and the `*` full-block marker, split out of RuleRepository.

extension RuleRepositoryAppScope on RuleRepository {
  /// `appScope` is a `|`-separated list, so the package may be the whole value or a slice.
  static String _scopeClause(String scopeColumn) =>
      '($scopeColumn = ? OR $scopeColumn LIKE ? OR $scopeColumn LIKE ? '
      'OR $scopeColumn LIKE ?)';

  static List<String> _scopeArgs(String packageName) => [
    packageName,
    '$packageName|%',
    '%|$packageName|%',
    '%|$packageName',
  ];

  /// Excludes the `*` full-block marker; sources are read, so all-disabled yields false.
  Future<List<MockRule>> loadForApp(String packageName) async {
    final subscriptions = await _subscriptionNames();
    final result = <MockRule>[];
    for (final kind in [RuleKind.block, RuleKind.allow]) {
      final rows = await _db.query(
        RuleRepository._ruleTables[kind]!,
        where:
            '${_scopeClause('appScope')} AND appInverted = 0 AND pattern <> ?',
        whereArgs: [..._scopeArgs(packageName), '*'],
        orderBy: 'id DESC',
      );
      if (rows.isEmpty) continue;
      final ids = [for (final row in rows) row['id'] as int];
      final placeholders = List.filled(ids.length, '?').join(',');
      final sourceRows = await _db.query(
        RuleRepository._sourceTables[kind]!,
        where: 'ruleId IN ($placeholders)',
        whereArgs: ids,
      );
      final byRule = <int, List<_SourceRef>>{};
      for (final row in sourceRows) {
        (byRule[row['ruleId'] as int] ??= []).add(
          _SourceRef(row['source'] as String, (row['enabled'] as int) == 1),
        );
      }
      result.addAll([
        for (final row in rows)
          _toRule(
            kind,
            row,
            byRule[row['id'] as int] ?? const [],
            subscriptions,
          ),
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
    final trimmed = pattern.trim();
    if (trimmed.isEmpty || packageName.trim().isEmpty) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final outcome = await _db.transaction<int?>((txn) async {
      final existing = await txn.query(
        RuleRepository._ruleTables[kind]!,
        columns: ['id'],
        where: 'pattern = ? AND important = ? AND appScope = ? AND appInverted = 0',
        whereArgs: [trimmed, important ? 1 : 0, packageName],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final id = existing.first['id'] as int;
        // Re-enable a disabled duplicate instead of silently no-oping.
        await txn.update(
          RuleRepository._ruleTables[kind]!,
          {'enabled': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await txn.insert(RuleRepository._sourceTables[kind]!, {
          'ruleId': id,
          'source': 'useradd',
          'enabled': 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        return null;
      }
      final id = await txn.insert(RuleRepository._ruleTables[kind]!, {
        'pattern': trimmed,
        'rawLine': trimmed,
        'addedAt': now,
        'enabled': 1,
        'important': important ? 1 : 0,
        'appScope': packageName,
        'appInverted': 0,
        'isWildcard': trimmed.contains('*') ? 1 : 0,
        'denyallow': null,
        'isRegex': 0,
        'dnsType': null,
      });
      await txn.insert(RuleRepository._sourceTables[kind]!, {
        'ruleId': id,
        'source': 'useradd',
        'enabled': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return id;
    });
    if (outcome == null) return null;
    return MockRule(
      id: '$outcome',
      pattern: trimmed,
      kind: kind,
      source: RuleSource.user,
      important: important,
      appScope: packageName,
    );
  }

  /// Whether the app has the `*` full-block rule (`*$app=<pkg>`).
  Future<bool> hasFullBlock(String packageName) async {
    final rows = await _db.query(
      'block_rule',
      columns: ['id'],
      where:
          'pattern = ? AND appInverted = 0 AND enabled = 1 '
          'AND ${_scopeClause('appScope')}',
      whereArgs: ['*', ..._scopeArgs(packageName)],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Enables or removes the app's `pattern = '*'` full-block rule; returns the new state.
  Future<bool> setFullBlock(String packageName, bool enabled) async {
    final existing = await _db.query(
      'block_rule',
      columns: ['id'],
      where: 'pattern = ? AND appInverted = 0 AND ${_scopeClause('appScope')}',
      whereArgs: ['*', ..._scopeArgs(packageName)],
      limit: 1,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      if (enabled) {
        final id = existing.isEmpty
            ? await txn.insert('block_rule', {
                'pattern': '*',
                'rawLine': '*\$app=$packageName',
                'addedAt': now,
                'enabled': 1,
                'important': 0,
                'appScope': packageName,
                'appInverted': 0,
                'isWildcard': 1,
                'denyallow': null,
                'isRegex': 0,
                'dnsType': null,
              })
            : existing.first['id'] as int;
        await txn.update(
          'block_rule',
          {'enabled': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        await txn.insert('block_rule_source', {
          'ruleId': id,
          'source': 'useradd',
          'enabled': 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } else if (existing.isNotEmpty) {
        final id = existing.first['id'] as int;
        await txn.delete('block_rule', where: 'id = ?', whereArgs: [id]);
        await txn.delete(
          'block_rule_source',
          where: 'ruleId = ?',
          whereArgs: [id],
        );
      }
    });
    return enabled;
  }
}
