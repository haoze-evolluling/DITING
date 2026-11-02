/// Read/write access to the legacy `mirror_template` table; templates carry `{url}` placeholders
/// substituted natively, so they are stored verbatim. The schema is never created here.
library;

import 'package:sqflite/sqflite.dart';

class MirrorTemplateRecord {
  const MirrorTemplateRecord({
    required this.id,
    required this.name,
    required this.template,
    required this.addedAt,
  });

  final int id;
  final String name;

  final String template;
  final int addedAt;

  static MirrorTemplateRecord fromRow(Map<String, Object?> row) =>
      MirrorTemplateRecord(
        id: (row['id'] as num?)?.toInt() ?? 0,
        name: row['name'] as String? ?? '',
        template: row['template'] as String? ?? '',
        addedAt: (row['addedAt'] as num?)?.toInt() ?? 0,
      );
}

/// Called after a write so the provider can bump its revision.
typedef MirrorTemplateWriteHook = void Function();

class MirrorTemplateRepository {
  MirrorTemplateRepository(this._db, {this.onChanged});

  final Database _db;
  final MirrorTemplateWriteHook? onChanged;

  void _changed() => onChanged?.call();

  Future<List<MirrorTemplateRecord>> all() async {
    final rows = await _db.query('mirror_template', orderBy: 'addedAt DESC');
    return [for (final row in rows) MirrorTemplateRecord.fromRow(row)];
  }

  Future<MirrorTemplateRecord?> byName(String name) async {
    final rows = await _db.query(
      'mirror_template',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    return rows.isEmpty ? null : MirrorTemplateRecord.fromRow(rows.first);
  }

  /// Inserts a template, returning null when the name is taken instead of replacing it.
  Future<int?> insert({required String name, required String template}) async {
    final trimmedName = name.trim();
    final trimmedTemplate = template.trim();
    if (trimmedName.isEmpty || trimmedTemplate.isEmpty) return null;
    if (await byName(trimmedName) != null) return null;
    final id = await _db.insert('mirror_template', {
      'name': trimmedName,
      'template': trimmedTemplate,
      'addedAt': DateTime.now().millisecondsSinceEpoch,
    });
    _changed();
    return id;
  }

  /// Renames and retargets a template; false when the name is taken.
  Future<bool> update({
    required int id,
    required String name,
    required String template,
  }) async {
    final trimmedName = name.trim();
    final trimmedTemplate = template.trim();
    if (trimmedName.isEmpty || trimmedTemplate.isEmpty) return false;
    final existing = await byName(trimmedName);
    if (existing != null && existing.id != id) return false;
    await _db.update(
      'mirror_template',
      {'name': trimmedName, 'template': trimmedTemplate},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changed();
    return true;
  }

  Future<void> delete(int id) async {
    await _db.delete('mirror_template', where: 'id = ?', whereArgs: [id]);
    _changed();
  }
}
