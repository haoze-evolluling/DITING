/// Read/write access to the legacy subscription tables; column names and ordering mirror the legacy
/// Room DAOs, because upgraded installs keep them.
library;

import 'package:diting_android/data/db/subscription_models.dart';
import 'package:sqflite/sqflite.dart';

typedef SubscriptionWriteHook = void Function();

class SubscriptionRepository {
  SubscriptionRepository(this._db, {this.onChanged});

  final Database _db;

  /// Called after every write so the provider layer can bump its revision.
  final SubscriptionWriteHook? onChanged;

  void _changed() => onChanged?.call();

  Future<List<SubscriptionRecord>> all() async =>
      _records(await _db.query('subscription', orderBy: 'addedAt DESC'));

  Future<List<SubscriptionRecord>> allRemote() async => _records(
    await _db.query(
      'subscription',
      where: "sourceType = 'remote'",
      orderBy: 'addedAt DESC',
    ),
  );

  /// Remote and enabled, ungrouped or in a group with auto-update on; the `LEFT JOIN` is what lets
  /// ungrouped rows through.
  Future<List<SubscriptionRecord>> allAutoUpdatableRemote() async => _records(
    await _db.rawQuery(
      'SELECT sub.* FROM subscription sub '
      'LEFT JOIN subscription_group grp ON grp.id = sub.groupId '
      "WHERE sub.sourceType = 'remote' AND sub.enabled = 1 "
      'AND (sub.groupId IS NULL OR grp.autoUpdateEnabled = 1) '
      'ORDER BY sub.addedAt DESC',
    ),
  );

  Future<List<SubscriptionRecord>> byKind(SubscriptionKind kind) async =>
      _records(
        await _db.query(
          'subscription',
          where: 'kind = ?',
          whereArgs: [kind.storageValue],
          orderBy: 'addedAt DESC',
        ),
      );

  Future<List<SubscriptionRecord>> remoteByKind(SubscriptionKind kind) async =>
      _records(
        await _db.query(
          'subscription',
          where: "sourceType = 'remote' AND kind = ?",
          whereArgs: [kind.storageValue],
          orderBy: 'addedAt DESC',
        ),
      );

  Future<SubscriptionRecord?> byId(int id) async =>
      _first(await _db.query('subscription', where: 'id = ?', whereArgs: [id]));

  /// The same address may exist once per kind (`(url, kind)` unique index).
  Future<SubscriptionRecord?> byUrlAndKind(
    String url,
    SubscriptionKind kind,
  ) async => _first(
    await _db.query(
      'subscription',
      where: 'url = ? AND kind = ?',
      whereArgs: [url, kind.storageValue],
      limit: 1,
    ),
  );

  Future<List<SubscriptionRecord>> byGroupId(int groupId) async => _records(
    await _db.query(
      'subscription',
      where: 'groupId = ?',
      whereArgs: [groupId],
      orderBy: 'addedAt DESC',
    ),
  );

  /// Both clauses matter: groups imported in one batch share `addedAt`, and `NOCASE` keeps the chip
  /// row stable across rebuilds.
  Future<List<SubscriptionGroupRecord>> groups() async {
    final rows = await _db.query(
      'subscription_group',
      orderBy: 'addedAt ASC, name COLLATE NOCASE ASC',
    );
    return SubscriptionGroupRecord.parseAll(rows);
  }

  Future<SubscriptionGroupRecord?> groupByName(String name) async =>
      _firstGroup(
        await _db.query(
          'subscription_group',
          where: 'name = ? COLLATE NOCASE',
          whereArgs: [name],
          limit: 1,
        ),
      );

  Future<List<SubscriptionAutoUpdateItemRecord>> autoUpdateItems(
    String batchId,
  ) async {
    final rows = await _db.query(
      'subscription_auto_update_item',
      where: 'batchId = ?',
      whereArgs: [batchId],
    );
    return SubscriptionAutoUpdateItemRecord.parseAll(rows);
  }

  /// Returns the id of an existing `(url, kind)` row instead of inserting a duplicate.
  Future<int> insert(SubscriptionRecord record) async {
    final existing = await byUrlAndKind(record.url, record.kind);
    if (existing != null) {
      return existing.id;
    }
    final id = await _db.insert('subscription', {
      'url': record.url,
      'name': record.name,
      'sourceType': record.sourceType.storageValue,
      'kind': record.kind.storageValue,
      'enabled': record.enabled ? 1 : 0,
      'ruleCount': record.ruleCount,
      'lastUpdated': record.lastUpdated,
      'addedAt': record.addedAt,
      'importState': record.importState.storageValue,
      'importError': record.importError,
      'httpEtag': record.httpEtag,
      'httpLastModified': record.httpLastModified,
      'ruleSetHash': record.ruleSetHash,
      'lastAttemptAt': record.lastAttemptAt,
      'consecutiveFailureCount': record.consecutiveFailureCount,
      'mirrorTemplate': record.mirrorTemplate,
      'mirrorFallback': record.mirrorFallback ? 1 : 0,
      'groupId': record.groupId,
    });
    _changed();
    return id;
  }

  Future<void> setEnabled(int id, bool enabled) async {
    await _db.update(
      'subscription',
      {'enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changed();
  }

  Future<void> setName(int id, String name) async {
    await _db.update(
      'subscription',
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changed();
  }

  /// Rewrites the user-editable columns. A changed address or kind invalidates the cached
  /// validators, otherwise the next update could get a 304 for content it never imported.
  Future<void> updateConfig(
    int id, {
    required String name,
    required String url,
    required SubscriptionKind kind,
    required int? groupId,
    required String? mirrorTemplate,
    required bool mirrorFallback,
    required bool resetValidators,
  }) async {
    await _db.update(
      'subscription',
      {
        'name': name,
        'url': url,
        'kind': kind.storageValue,
        'groupId': groupId,
        'mirrorTemplate': mirrorTemplate,
        'mirrorFallback': mirrorFallback ? 1 : 0,
        if (resetValidators) ...{'httpEtag': null, 'httpLastModified': null},
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _changed();
  }

  Future<void> clearGroup(int groupId) async {
    await _db.update(
      'subscription',
      {'groupId': null},
      where: 'groupId = ?',
      whereArgs: [groupId],
    );
    _changed();
  }

  Future<void> setDetails(
    int id, {
    required String name,
    required String url,
    required int ruleCount,
    required int lastUpdated,
  }) async {
    await _db.update(
      'subscription',
      {
        'name': name,
        'url': url,
        'ruleCount': ruleCount,
        'lastUpdated': lastUpdated,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _changed();
  }

  Future<void> setImportState(
    int id,
    SubscriptionImportState state, {
    String? error,
  }) async {
    await _db.update(
      'subscription',
      {'importState': state.storageValue, 'importError': error},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changed();
  }

  /// Records a successful import. `ruleSetHash` is the content hash of the stored rules, so the
  /// version history (R6) and the subscription row agree on which snapshot is current.
  Future<void> markImported(
    int id, {
    required int ruleCount,
    required int lastUpdated,
    required String? etag,
    required String? lastModified,
    String? ruleSetHash,
  }) async {
    await _db.update(
      'subscription',
      {
        'ruleCount': ruleCount,
        'lastUpdated': lastUpdated,
        'importState': SubscriptionImportState.ready.storageValue,
        'importError': null,
        'httpEtag': etag,
        'httpLastModified': lastModified,
        'ruleSetHash': ruleSetHash,
        'lastAttemptAt': lastUpdated,
        'consecutiveFailureCount': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _changed();
  }

  /// Records a 304 without touching `ruleCount` or `lastUpdated`; the content is unchanged.
  Future<void> markNotModified(
    int id, {
    required int attemptedAt,
    String? etag,
    String? lastModified,
  }) async {
    await _db.update(
      'subscription',
      {
        'importState': SubscriptionImportState.ready.storageValue,
        'importError': null,
        'lastAttemptAt': attemptedAt,
        'consecutiveFailureCount': 0,
        'httpEtag': etag,
        'httpLastModified': lastModified,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _changed();
  }

  /// Increments the failure counter rather than setting it to 1, because retry backoff depends on
  /// the count.
  Future<void> markUpdateFailed(
    int id, {
    required String error,
    required int attemptedAt,
  }) async {
    await _db.rawUpdate(
      'UPDATE subscription SET importState = ?, importError = ?, '
      'lastAttemptAt = ?, '
      'consecutiveFailureCount = consecutiveFailureCount + 1 WHERE id = ?',
      [SubscriptionImportState.failed.storageValue, error, attemptedAt, id],
    );
    _changed();
  }

  /// Clears counts and validators after the rule tables are wiped; a stale validator would earn a
  /// 304 and leave the UI showing rules the database no longer holds.
  Future<void> resetAfterRuleCleanup() async {
    await _db.update('subscription', {
      'ruleCount': 0,
      'lastUpdated': 0,
      'httpEtag': null,
      'httpLastModified': null,
      'ruleSetHash': null,
    });
    _changed();
  }

  /// The cascade relies on `PRAGMA foreign_keys`, set per connection when opening.
  Future<void> deleteById(int id) async {
    await _db.delete('subscription', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> deleteByKind(SubscriptionKind kind) async {
    await _db.delete(
      'subscription',
      where: 'kind = ?',
      whereArgs: [kind.storageValue],
    );
    _changed();
  }

  /// Returns the id of an existing group with the same case-insensitive name.
  Future<int> insertGroup({
    required String name,
    bool autoUpdateEnabled = true,
    int? addedAt,
  }) async {
    final existing = await groupByName(name);
    if (existing != null) {
      return existing.id;
    }
    final id = await _db.insert('subscription_group', {
      'name': name,
      'autoUpdateEnabled': autoUpdateEnabled ? 1 : 0,
      'addedAt': addedAt ?? DateTime.now().millisecondsSinceEpoch,
    });
    _changed();
    return id;
  }

  Future<void> setGroupName(int id, String name) async {
    await _db.update(
      'subscription_group',
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changed();
  }

  Future<void> setGroupAutoUpdateEnabled(int id, bool enabled) async {
    await _db.update(
      'subscription_group',
      {'autoUpdateEnabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changed();
  }

  /// Ungroups the group's subscriptions, then deletes the group row; both statements must share one
  /// transaction, or a failure leaves subscriptions pointing at a missing group.
  Future<void> dissolveGroup(int id) async {
    await _db.transaction((txn) async {
      await txn.update(
        'subscription',
        {'groupId': null},
        where: 'groupId = ?',
        whereArgs: [id],
      );
      await txn.delete('subscription_group', where: 'id = ?', whereArgs: [id]);
    });
    _changed();
  }

  Future<void> deleteGroupById(int id) async {
    await _db.delete('subscription_group', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  static List<SubscriptionRecord> _records(List<Map<String, Object?>> rows) =>
      SubscriptionRecord.parseAll(rows);

  static SubscriptionRecord? _first(List<Map<String, Object?>> rows) {
    final parsed = SubscriptionRecord.parseAll(rows);
    return parsed.isEmpty ? null : parsed.first;
  }

  static SubscriptionGroupRecord? _firstGroup(List<Map<String, Object?>> rows) {
    final parsed = SubscriptionGroupRecord.parseAll(rows);
    return parsed.isEmpty ? null : parsed.first;
  }
}
