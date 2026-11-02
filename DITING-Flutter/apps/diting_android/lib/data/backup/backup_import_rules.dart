part of 'backup_importer.dart';

/// Merge of subscription and rule groups; a missing rule database is a failure, never silently
/// skipped.
extension _BackupImportRules on BackupImporter {
  Future<BackupGroupOutcome> _importSubscriptions(
    Object? value,
    BackupImportTarget target,
  ) async {
    if (value is! Map) {
      throw BackupFormatException(currentL10n.backupErrSubsNotObject);
    }
    final db = target.database;
    if (db == null) {
      throw BackupFormatException(currentL10n.backupErrNoRuleDbSubs);
    }
    final repository = SubscriptionRepository(db);
    final groupsValue = value['groups'];
    final groupIdByName = <String, int>{};
    var added = 0;
    var skipped = 0;
    var updated = 0;

    if (groupsValue is List) {
      for (final item in groupsValue) {
        if (item is! Map) continue;
        final name = item['name'];
        if (name is! String || name.trim().isEmpty) continue;
        final existing = await repository.groupByName(name);
        if (existing == null) {
          final id = await repository.insertGroup(
            name: name,
            autoUpdateEnabled: item['autoUpdateEnabled'] != false,
          );
          groupIdByName[name] = id;
          added++;
        } else {
          groupIdByName[name] = existing.id;
          skipped++;
        }
      }
    }

    await _importMirrorTemplates(db, value['mirrorTemplates']);

    final items = value['items'];
    if (items is List) {
      for (final item in items) {
        if (item is! Map) {
          skipped++;
          continue;
        }
        final url = item['url'];
        if (url is! String || url.trim().isEmpty) {
          skipped++;
          continue;
        }
        final kind = SubscriptionKind.normalize(item['kind'] as String?);
        final existing = await repository.byUrlAndKind(url, kind);
        if (existing != null) {
          skipped++;
          continue;
        }
        final groupName = item['groupName'];
        final now = DateTime.now().millisecondsSinceEpoch;
        await repository.insert(
          SubscriptionRecord(
            id: 0,
            url: url,
            name: item['name'] as String? ?? url,
            sourceType: SubscriptionSourceType.fromStorage(
              item['sourceType'] as String?,
            ),
            kind: kind,
            enabled: item['enabled'] != false,
            // Importing the URL, not its contents: zero count and untouched timestamps so the first
            // refresh downloads.
            ruleCount: 0,
            lastUpdated: 0,
            addedAt: now,
            importState: SubscriptionImportState.ready,
            lastAttemptAt: 0,
            consecutiveFailureCount: 0,
            mirrorTemplate: item['mirrorTemplate'] as String?,
            mirrorFallback: item['mirrorFallback'] != false,
            groupId: groupName is String ? groupIdByName[groupName] : null,
          ),
        );
        added++;
      }
    }

    return BackupGroupOutcome(
      group: BackupGroup.subscriptions,
      added: added,
      skipped: skipped,
      updated: updated,
    );
  }

  /// Mirror templates, deduped by name; the table has no incremental write path.
  Future<void> _importMirrorTemplates(Database db, Object? value) async {
    if (value is! List) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final item in value) {
      if (item is! Map) continue;
      final name = item['name'];
      final template = item['template'];
      if (name is! String || name.trim().isEmpty) continue;
      if (template is! String || template.trim().isEmpty) continue;
      await db.insert('mirror_template', {
        'name': name.trim(),
        'template': template.trim(),
        'addedAt': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }
}

extension _BackupImportRuleTables on BackupImporter {
  /// Block and allow rules share one list, split by `kind`. Dedupe by `pattern` without
  /// overwriting, or per-app rules degrade into global blocks.
  Future<BackupGroupOutcome> _importRules(
    Object? value,
    BackupImportTarget target,
    BackupGroup group,
  ) async {
    if (value is! List) {
      throw BackupFormatException(currentL10n.backupErrRulesNotArray);
    }
    final db = target.database;
    if (db == null) {
      throw BackupFormatException(currentL10n.backupErrNoRuleDbRules);
    }
    final existing = {'block': <String>{}, 'allow': <String>{}};
    final repository = RuleRepository(db);
    for (final entry in existing.entries) {
      final kind = entry.key == 'allow' ? RuleKind.allow : RuleKind.block;
      for (final rule in await repository.loadKind(kind)) {
        entry.value.add(_ruleKey(rule.pattern, rule.important, rule.appScope));
      }
    }
    var added = 0;
    var skipped = 0;
    for (final item in value) {
      if (item is! Map) {
        skipped++;
        continue;
      }
      final pattern = item['pattern'];
      if (pattern is! String || pattern.trim().isEmpty) {
        skipped++;
        continue;
      }
      final isAllow = item['kind'] == 'allow';
      final table = isAllow ? 'allow_rule' : 'block_rule';
      final important = item['important'] == true;
      final appScope = _text(item['appScope']);
      final key = _ruleKey(pattern.trim(), important, appScope);
      if (!existing[isAllow ? 'allow' : 'block']!.add(key)) {
        skipped++;
        continue;
      }
      await _insertDomainRule(db, table, item, pattern.trim());
      added++;
    }
    return BackupGroupOutcome(group: group, added: added, skipped: skipped);
  }

  /// Dedupe key matching the unique indexes on the block/allow rule tables.
  String _ruleKey(String pattern, bool important, String? appScope) =>
      '$pattern\u0000${important ? 1 : 0}\u0000${appScope ?? ''}';

  String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _insertDomainRule(
    Database db,
    String table,
    Map item,
    String pattern,
  ) async {
    final rawLine = _text(item['rawLine']) ?? pattern;
    final appScope = _text(item['appScope']);
    await db.insert(table, {
      'pattern': pattern,
      'rawLine': rawLine,
      'addedAt': DateTime.now().millisecondsSinceEpoch,
      'enabled': item['enabled'] == false ? 0 : 1,
      'groupName': _text(item['group']),
      'important': item['important'] == true ? 1 : 0,
      'appScope': appScope,
      'appInverted': item['appInverted'] == true ? 1 : 0,
      'isWildcard': pattern.contains('*') ? 1 : 0,
      'denyallow': null,
      'isRegex': 0,
      'dnsType': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    // whereArgs rejects null, so an empty appScope must use `IS NULL`.
    final rows = await db.query(
      table,
      columns: ['id'],
      where: appScope == null
          ? 'pattern = ? AND important = ? AND appScope IS NULL'
          : 'pattern = ? AND important = ? AND appScope = ?',
      whereArgs: [pattern, item['important'] == true ? 1 : 0, ?appScope],
      limit: 1,
    );
    if (rows.isEmpty) return;
    await db.insert('${table}_source', {
      'ruleId': rows.first['id'],
      'source': 'useradd',
      'enabled': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Rewrite rules: same pattern and targetType with a different value is updated.
  Future<BackupGroupOutcome> _importRewrite(
    Object? value,
    BackupImportTarget target,
    Set<String> targetTypes,
    BackupGroup group,
  ) async {
    if (value is! List) {
      throw BackupFormatException(currentL10n.backupErrRewriteNotArray);
    }
    final db = target.database;
    if (db == null) {
      throw BackupFormatException(currentL10n.backupErrNoRuleDbRewrite);
    }
    var added = 0;
    var skipped = 0;
    var updated = 0;
    for (final item in value) {
      if (item is! Map) {
        skipped++;
        continue;
      }
      final pattern = item['pattern'];
      final targetValue = item['targetValue'];
      final targetType = item['targetType'];
      if (pattern is! String ||
          pattern.trim().isEmpty ||
          targetValue is! String ||
          targetType is! String ||
          !targetTypes.contains(targetType)) {
        skipped++;
        continue;
      }
      final existing = await db.query(
        'rewrite_rule',
        columns: ['id', 'targetValue'],
        where: 'pattern = ? AND targetType = ?',
        whereArgs: [pattern.trim(), targetType],
        limit: 1,
      );
      if (existing.isEmpty) {
        await _insertRewrite(db, item, pattern.trim(), targetType, targetValue);
        added++;
      } else if (existing.first['targetValue'] == targetValue) {
        skipped++;
      } else {
        await db.update(
          'rewrite_rule',
          {
            'targetValue': targetValue,
            'rawLine':
                _text(item['rawLine']) ?? '${pattern.trim()} $targetValue',
          },
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
        updated++;
      }
    }
    return BackupGroupOutcome(
      group: group,
      added: added,
      skipped: skipped,
      updated: updated,
    );
  }

  Future<void> _insertRewrite(
    Database db,
    Map item,
    String pattern,
    String targetType,
    String targetValue,
  ) async {
    final id = await db.insert('rewrite_rule', {
      'pattern': pattern,
      'targetType': targetType,
      'targetValue': targetValue,
      'rawLine': _text(item['rawLine']) ?? '$pattern $targetValue',
      'addedAt': DateTime.now().millisecondsSinceEpoch,
      'enabled': item['enabled'] == false ? 0 : 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id == 0) return;
    await db.insert('rewrite_rule_source', {
      'ruleId': id,
      'source': 'useradd',
      'enabled': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Address (URL/CNAME) rules: dedupe by `pattern` + `kind`, insert only.
  Future<BackupGroupOutcome> _importAddressRules(
    Object? value,
    BackupImportTarget target,
  ) async {
    if (value is! List) {
      throw BackupFormatException(currentL10n.backupErrAddressNotArray);
    }
    final db = target.database;
    if (db == null) {
      throw BackupFormatException(currentL10n.backupErrNoRuleDbAddress);
    }
    var added = 0;
    var skipped = 0;
    for (final item in value) {
      if (item is! Map) {
        skipped++;
        continue;
      }
      final pattern = item['pattern'];
      final kind = item['kind'];
      if (pattern is! String ||
          pattern.trim().isEmpty ||
          kind is! String ||
          kind.isEmpty) {
        skipped++;
        continue;
      }
      final existing = await db.query(
        'go_url_rule',
        columns: ['id'],
        where: 'pattern = ? AND kind = ?',
        whereArgs: [pattern.trim(), kind],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        skipped++;
        continue;
      }
      final id = await db.insert('go_url_rule', {
        'pattern': pattern.trim(),
        'kind': kind,
        'rawLine': _text(item['rawLine']) ?? pattern.trim(),
        'addedAt': DateTime.now().millisecondsSinceEpoch,
        'enabled': item['enabled'] == false ? 0 : 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      if (id != 0) {
        await db.insert('go_url_rule_source', {
          'ruleId': id,
          'source': 'useradd',
          'enabled': 1,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      added++;
    }
    return BackupGroupOutcome(
      group: BackupGroup.addressRules,
      added: added,
      skipped: skipped,
    );
  }
}
