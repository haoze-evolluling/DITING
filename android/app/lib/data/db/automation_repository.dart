/// Read/write access to the `automation_*` tables (A1 / A3 / A14).
library;

import 'package:diting_android/data/db/automation_models.dart';
import 'package:sqflite/sqflite.dart';

typedef AutomationWriteHook = void Function();

class AutomationRepository {
  AutomationRepository(this._db, {this.onChanged});

  final Database _db;

  /// Called after every write so the provider layer can bump its revision.
  final AutomationWriteHook? onChanged;

  void _changed() => onChanged?.call();

  Future<List<AutomationRule>> rules() async {
    final rows = await _db.query(
      'automation_rule',
      orderBy: 'priority DESC, updated_at DESC',
    );
    return [for (final row in rows) AutomationRule.fromRow(row)];
  }

  Future<AutomationRule?> rule(String id) async {
    final rows = await _db.query(
      'automation_rule',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : AutomationRule.fromRow(rows.first);
  }

  Future<void> saveRule(AutomationRule rule) async {
    // Replace, not upsert-by-diff: the whole document is the unit the editor edits.
    await _db.insert(
      'automation_rule',
      rule.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _changed();
  }

  Future<void> setRuleEnabled(String id, bool enabled) async {
    await _db.update(
      'automation_rule',
      {'enabled': enabled ? 1 : 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changed();
  }

  Future<void> deleteRule(String id) async {
    await _db.delete('automation_rule', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<List<AutomationProfile>> profiles() async {
    final rows = await _db.query('automation_profile', orderBy: 'updated_at DESC');
    return [for (final row in rows) AutomationProfile.fromRow(row)];
  }

  Future<void> saveProfile(AutomationProfile profile) async {
    await _db.insert(
      'automation_profile',
      profile.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _changed();
  }

  Future<void> deleteProfile(String id) async {
    await _db.delete('automation_profile', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<List<AutomationEvent>> events({int limit = 200}) async {
    final rows = await _db.query(
      'automation_event',
      orderBy: 'ts DESC',
      limit: limit,
    );
    return [for (final row in rows) AutomationEvent.fromRow(row)];
  }

  Future<void> logEvent(AutomationEvent event) async {
    // The audit timeline is append-only; deleting a rule must not erase its history.
    await _db.insert('automation_event', event.toRow());
    _changed();
  }
}
