// R6: the rule-set version store and the native diff/record kernel.
//
// Uses an in-memory sqflite database for the store and the real Rust core for the diff and the
// retention decision, so the preview and the stored history come from the same implementation.

import 'package:diting_android/data/db/rule_version_repository.dart';
import 'package:diting_android/data/rules/rust_rule_version_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('规则版本存储', () {
    late Database db;
    late RuleVersionRepository repository;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      repository = RuleVersionRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('首次记录后成为唯一最新版本', () async {
      final rules = ['||a.com^', '||b.com^', '||c.com^'];
      await repository.recordVersion(
        groupId: 'sub_1',
        hash: ruleSetHash(rules),
        ruleCount: rules.length,
        rules: rules,
      );
      final history = await repository.history('sub_1');
      expect(history, hasLength(1));
      expect(history.first.rules, rules);
      expect(history.first.ruleCount, 3);
      expect(history.first.hash, ruleSetHash(rules));
    });

    test('新版本在前，且能对上一版本做 diff', () async {
      final v1 = ['||a.com^', '||b.com^', '||c.com^'];
      final v2 = ['||a.com^', '||b.com^', '||d.com^'];
      await repository.recordVersion(
        groupId: 'sub_1',
        hash: ruleSetHash(v1),
        ruleCount: 3,
        rules: v1,
      );
      await repository.recordVersion(
        groupId: 'sub_1',
        hash: ruleSetHash(v2),
        ruleCount: 3,
        rules: v2,
      );
      final history = await repository.history('sub_1');
      expect(history, hasLength(2));
      expect(history.first.rules, v2);
      expect(history.last.rules, v1);

      final diff = RustRuleVersionCore.instance.diff(history.last.rules, history.first.rules);
      expect(diff.added, ['||d.com^']);
      expect(diff.removed, ['||c.com^']);
      expect(diff.addedCount, 1);
      expect(diff.removedCount, 1);
      expect(diff.unchangedCount, 2);
    });

    test('内容未变时不重复记录', () async {
      final rules = ['||a.com^'];
      final hash = ruleSetHash(rules);
      await repository.recordVersion(
        groupId: 'sub_1',
        hash: hash,
        ruleCount: 1,
        rules: rules,
      );
      await repository.recordVersion(
        groupId: 'sub_1',
        hash: hash,
        ruleCount: 1,
        rules: rules,
      );
      expect(await repository.history('sub_1'), hasLength(1));
    });

    test('历史按内核保留窗口裁剪（默认 10）', () async {
      for (var i = 0; i < 14; i++) {
        final rules = ['||v$i.com^'];
        await repository.recordVersion(
          groupId: 'sub_1',
          hash: ruleSetHash(rules),
          ruleCount: 1,
          rules: rules,
        );
      }
      final history = await repository.history('sub_1', limit: 50);
      expect(history, hasLength(10));
      // Newest first: the last recorded version is the head.
      expect(history.first.rules, ['||v13.com^']);
      expect(history.last.rules, ['||v4.com^']);
    });

    test('不同分组互不影响', () async {
      await repository.recordVersion(
        groupId: 'sub_1',
        hash: ruleSetHash(['||a^']),
        ruleCount: 1,
        rules: ['||a^'],
      );
      expect(await repository.history('sub_2'), isEmpty);
    });
  });

  group('ruleSetHash', () {
    test('确定且对顺序敏感', () {
      expect(ruleSetHash(['a', 'b']), ruleSetHash(['a', 'b']));
      expect(ruleSetHash(['a', 'b']), isNot(ruleSetHash(['b', 'a'])));
      expect(ruleSetHash(['ab', 'c']), isNot(ruleSetHash(['a', 'bc'])));
    });
  });
}
