part of 'backup_exporter.dart';

// Subscription and rule groups of the backup export.

extension _BackupRuleExport on BackupExporter {
  Future<Object?> _subscriptions(BackupExportSource source) async {
    final db = source.database;
    if (db == null) return const [];
    final repository = SubscriptionRepository(db);
    final groups = await repository.groups();
    final rows = await repository.all();
    // `mirror_template` has no repository layer; early databases may lack the table.
    var templates = const <Map<String, Object?>>[];
    if (await _hasTable(db, 'mirror_template')) {
      templates = await db.query(
        'mirror_template',
        columns: ['name', 'template'],
        orderBy: 'name',
      );
    }
    return {
      'groups': [
        for (final group in groups)
          {'name': group.name, 'autoUpdateEnabled': group.autoUpdateEnabled},
      ],
      'mirrorTemplates': [
        for (final row in templates)
          {'name': row['name'], 'template': row['template']},
      ],
      'items': [
        for (final row in rows)
          {
            'url': row.url,
            'name': row.name,
            'kind': row.kind.storageValue,
            'scope': 'dns',
            'sourceType': row.sourceType.storageValue,
            'enabled': row.enabled,
            'groupName': _groupNameOf(groups, row.groupId),
            'mirrorTemplate': row.mirrorTemplate,
            'mirrorFallback': row.mirrorFallback,
          },
      ],
    };
  }

  Future<bool> _hasTable(Database db, String name) async {
    final rows = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: ['table', name],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  String? _groupNameOf(List<SubscriptionGroupRecord> groups, int? groupId) {
    if (groupId == null) return null;
    for (final group in groups) {
      if (group.id == groupId) return group.name;
    }
    return null;
  }

  /// Block and allow rules share one group, split by each rule's `kind`; `appScope`, `appInverted`
  /// and `rawLine` must be kept.
  Future<Object?> _rules(BackupExportSource source, BackupGroup group) async {
    final db = source.database;
    if (db == null) return const [];
    final exported = <Object?>[];
    for (final kind in const [RuleKind.block, RuleKind.allow]) {
      final rows = await _userRuleRows(
        db,
        table: kind == RuleKind.block ? 'block_rule' : 'allow_rule',
        sourceTable: kind == RuleKind.block
            ? 'block_rule_source'
            : 'allow_rule_source',
      );
      for (final row in rows) {
        exported.add({
          'pattern': row['pattern'],
          'kind': kind == RuleKind.allow ? 'allow' : 'block',
          'enabled': (row['enabled'] as int? ?? 1) == 1,
          'important': (row['important'] as int? ?? 0) == 1,
          'appScope': row['appScope'],
          'appInverted': (row['appInverted'] as int? ?? 0) == 1,
          'rawLine': row['rawLine'],
          'group': row['groupName'],
        });
      }
    }
    return exported;
  }

  /// User-origin rows of [table], filtered inside SQLite.
  ///
  /// Only user rules are exported, but the filter has to run in SQL: reading the whole table and
  /// dropping subscription rows in Dart materialized every row of a subscription-sized dataset in
  /// the ART heap, which is what killed the process during an export (2026-10-31 log: heap climbed
  /// to 255MB/256MB and the last three seconds were GC-thrash). `*_source(source)` is indexed, so
  /// the join only touches the user rows.
  Future<List<Map<String, Object?>>> _userRuleRows(
    Database db, {
    required String table,
    required String sourceTable,
  }) => db.rawQuery(
    'SELECT r.* FROM $table r '
    'JOIN $sourceTable s ON s.ruleId = r.id '
    'WHERE s.source IN '
    '(${List.filled(RuleRepository.userSources.length, '?').join(',')}) '
    'GROUP BY r.id ORDER BY r.id DESC',
    RuleRepository.userSources,
  );

  /// Rewrite rules, split by `targetType` into IPv4/IPv6 and CNAME.
  ///
  /// Both groups split the same table, so the rows are read once per export and reused; a rule with
  /// several user sources appears once.
  Future<Object?> _rewriteRules(
    BackupExportSource source,
    Set<String> targetTypes,
    Map<String, Object?> cache,
  ) async {
    final db = source.database;
    if (db == null) return const [];
    final rows = await _cachedUserRewriteRows(db, cache);
    return [
      for (final row in rows)
        if (targetTypes.contains(row['targetType']))
          {
            'pattern': row['pattern'],
            'targetType': row['targetType'],
            'targetValue': row['targetValue'],
            'rawLine': row['rawLine'],
            'enabled': (row['enabled'] as int? ?? 1) == 1,
          },
    ];
  }

  Future<List<Map<String, Object?>>> _cachedUserRewriteRows(
    Database db,
    Map<String, Object?> cache,
  ) async {
    final cached = cache['rewrite'];
    if (cached is List<Map<String, Object?>>) return cached;
    final rows = await _userRuleRows(
      db,
      table: 'rewrite_rule',
      sourceTable: 'rewrite_rule_source',
    );
    cache['rewrite'] = rows;
    return rows;
  }

  Object? _addressRules(BackupExportSource source) async {
    final db = source.database;
    if (db == null) return const [];
    final rows = await _userRuleRows(
      db,
      table: 'go_url_rule',
      sourceTable: 'go_url_rule_source',
    );
    return [
      for (final row in rows)
        {
          'pattern': row['pattern'],
          'kind': row['kind'],
          'rawLine': row['rawLine'],
          'enabled': (row['enabled'] as int? ?? 1) == 1,
        },
    ];
  }
}
