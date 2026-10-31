// Rule table SQL and app-scoped rules: the blacklist must never treat an app rule as
// global, and an unavailable rule library must report itself as unavailable.

import 'package:diting/data/db/datasets.dart';
import 'package:diting/data/db/legacy_database.dart';
import 'package:diting/data/db/preset_whitelist.dart';
import 'package:diting/data/db/rule_bootstrap.dart';
import 'package:diting/data/db/rule_providers.dart';
import 'package:diting/data/db/rule_repository.dart';
import 'package:diting/data/mock_data.dart';
import 'package:diting/data/prefs/legacy_prefs_store.dart';
import 'package:diting/data/prefs/legacy_settings.dart';
import 'package:diting/state/app_rules_providers.dart';
import 'package:diting/state/rules_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

part 'rule_repository_test_app_scope.dart';

void main() {
  group('规则表 SQL', _ruleRepository);
  group('应用独立规则', _appScopedRules);
  group('数据集规则库', _ruleDataSets);
}

/// Every work mode opens its own legacy database and records the seed marker in its own container.
void _ruleDataSets() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('bootstrapRules 按数据集打开规则库并写数据集种子标记', () async {
    final store = MemoryLegacyPrefsStore();
    final settings = LegacySettings(
      store,
      dnsContainer: LegacySettings.expressContainer,
    );
    addTearDown(() async {
      final path = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(
        '$path/${LegacyDatabase.expressFile}',
      );
    });

    final boot = await bootstrapRules(
      DataSet.express,
      settings,
      versionCode: 9,
    );

    expect(boot.repository, isNotNull);
    expect(boot.repository!.sourceFile, LegacyDatabase.expressFile);
    expect(
      store.read(
        LegacySettings.expressContainer,
        'default_whitelist_initialized',
      ),
      isTrue,
    );
    expect(
      store.read(LegacySettings.uiContainer, 'default_whitelist_initialized'),
      isNull,
    );
  });
}

/// Exercises the SQL against the exact 1.4.3 layout, a subset of `AppDatabase` v3
void _ruleRepository() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE block_rule (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'pattern TEXT NOT NULL, rawLine TEXT NOT NULL, addedAt INTEGER NOT NULL, '
      'enabled INTEGER NOT NULL, groupName TEXT, important INTEGER NOT NULL, '
      'appScope TEXT, appInverted INTEGER NOT NULL, isWildcard INTEGER NOT NULL, '
      'denyallow TEXT, isRegex INTEGER NOT NULL, dnsType TEXT)',
    );
    await db.execute(
      'CREATE TABLE block_rule_source (ruleId INTEGER NOT NULL, source TEXT NOT NULL, '
      'enabled INTEGER NOT NULL, PRIMARY KEY(ruleId, source), '
      'FOREIGN KEY(ruleId) REFERENCES block_rule(id) ON DELETE CASCADE)',
    );
    await db.execute(
      'CREATE TABLE allow_rule (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'pattern TEXT NOT NULL, rawLine TEXT NOT NULL, addedAt INTEGER NOT NULL, '
      'enabled INTEGER NOT NULL, groupName TEXT, appScope TEXT, '
      'appInverted INTEGER NOT NULL, isWildcard INTEGER NOT NULL, '
      'important INTEGER NOT NULL, denyallow TEXT, isRegex INTEGER NOT NULL, '
      'dnsType TEXT)',
    );
    await db.execute(
      'CREATE TABLE allow_rule_source (ruleId INTEGER NOT NULL, source TEXT NOT NULL, '
      'enabled INTEGER NOT NULL, PRIMARY KEY(ruleId, source), '
      'FOREIGN KEY(ruleId) REFERENCES allow_rule(id) ON DELETE CASCADE)',
    );
    await db.execute(
      'CREATE TABLE rewrite_rule (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'pattern TEXT NOT NULL, targetType TEXT NOT NULL, targetValue TEXT NOT NULL, '
      'rawLine TEXT NOT NULL, addedAt INTEGER NOT NULL, enabled INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE rewrite_rule_source (ruleId INTEGER NOT NULL, source TEXT NOT NULL, '
      'enabled INTEGER NOT NULL, PRIMARY KEY(ruleId, source), '
      'FOREIGN KEY(ruleId) REFERENCES rewrite_rule(id) ON DELETE CASCADE)',
    );
    await db.execute(
      'CREATE TABLE subscription (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'name TEXT NOT NULL)',
    );
    await db.execute('PRAGMA foreign_keys = ON');
  });

  tearDown(() => db.close());

  Future<int> insertBlock(
    String pattern, {
    bool enabled = true,
    bool important = false,
    String source = 'useradd',
    bool sourceEnabled = true,
  }) async {
    final id = await db.insert('block_rule', {
      'pattern': pattern,
      'rawLine': pattern,
      'addedAt': 1,
      'enabled': enabled ? 1 : 0,
      'important': important ? 1 : 0,
      'appScope': null,
      'appInverted': 0,
      'isWildcard': 0,
      'isRegex': 0,
    });
    await db.insert('block_rule_source', {
      'ruleId': id,
      'source': source,
      'enabled': sourceEnabled ? 1 : 0,
    });
    return id;
  }

  group('读取', () {
    test('来源标签映射 preset / sub_<id> / 用户', () async {
      await db.insert('subscription', {'id': 7, 'name': '订阅甲'});
      await insertBlock('preset.example', source: 'preset');
      await insertBlock('sub.example', source: 'sub_7');
      await insertBlock('user.example', source: 'useradd');

      final rules = await RuleRepository(db).loadKind(RuleKind.block);
      final byPattern = {for (final rule in rules) rule.pattern: rule};

      expect(rules, hasLength(3));
      expect(byPattern['user.example']!.source, RuleSource.user);
      expect(byPattern['sub.example']!.source, RuleSource.subscription);
      expect(byPattern['sub.example']!.subscriptionName, '订阅甲');
      expect(byPattern['preset.example']!.source, RuleSource.preset);
    });

    test('countUser 只数用户来源，且多来源不重复计数', () async {
      await insertBlock('user.example');
      await insertBlock('imported.example', source: 'local_import');
      await insertBlock('preset.example', source: 'preset');
      await insertBlock('sub.example', source: 'sub_7');
      final both = await insertBlock('both.example');
      await db.insert('block_rule_source', {
        'ruleId': both,
        'source': 'local_hosts',
        'enabled': 1,
      });

      // 三张表里只有 block_rule 有行，allow / rewrite 计 0。
      expect(await RuleRepository(db).countUser(), 3);
    });

    test('规则或来源任一禁用即视为禁用', () async {
      await insertBlock('off-rule.example', enabled: false);
      await insertBlock('off-source.example', sourceEnabled: false);
      await insertBlock('on.example');

      final rules = await RuleRepository(db).loadKind(RuleKind.block);
      final byPattern = {for (final rule in rules) rule.pattern: rule};

      expect(byPattern['off-rule.example']!.enabled, isFalse);
      expect(byPattern['off-source.example']!.enabled, isFalse);
      expect(byPattern['on.example']!.enabled, isTrue);
    });
  });

  group('写入', () {
    test('新增写入 useradd 来源，重复 pattern 复用同一行', () async {
      final repo = RuleRepository(db);
      final first = await repo.add(RuleKind.block, '||ads.example^');
      final second = await repo.add(RuleKind.block, '||ads.example^');

      expect(second.id, first.id);
      expect(await db.query('block_rule'), hasLength(1));
      expect(
        await db.query(
          'block_rule_source',
          where: 'source = ?',
          whereArgs: ['useradd'],
        ),
        hasLength(1),
      );
    });

    test('删除规则级联删除来源', () async {
      final id = await insertBlock('gone.example');
      await RuleRepository(db).delete(RuleKind.block, id);

      expect(await db.query('block_rule'), isEmpty);
      expect(await db.query('block_rule_source'), isEmpty);
    });

    test('清空自定义只删用户来源，订阅行保留', () async {
      final user = await insertBlock('user.example');
      final sub = await insertBlock('sub.example', source: 'sub_1');
      await db.insert('block_rule_source', {
        'ruleId': sub,
        'source': 'useradd',
        'enabled': 1,
      });

      await RuleRepository(db).clearUser(RuleKind.block);

      final remaining = await db.query('block_rule');
      expect(remaining.map((row) => row['id']), [sub]);
      expect(
        await db.query(
          'block_rule_source',
          where: 'ruleId = ?',
          whereArgs: [user],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'block_rule_source',
          where: 'ruleId = ? AND source = ?',
          whereArgs: [sub, 'useradd'],
        ),
        isEmpty,
      );
    });
  });

  group('预设资产解析', () {
    test('忽略注释与重复、去尾点、小写', () {
      final entries = parsePresetWhitelist('''
# 标题
# Format: bare domain
# 分类A
Example.COM.
example.com
# 分类B
b.example//comment
// 分类C
c.example
''');
      expect(entries.map((entry) => entry.domain), [
        'example.com',
        'b.example//comment',
        'c.example',
      ]);
      expect(entries.first.group, '分类A');
    });
  });

  group('应用作用域', () {
    Future<int> insertScoped(
      String pattern,
      String? appScope, {
      bool important = false,
    }) async {
      final id = await db.insert('block_rule', {
        'pattern': pattern,
        'rawLine': pattern,
        'addedAt': 1,
        'enabled': 1,
        'important': important ? 1 : 0,
        'appScope': appScope,
        'appInverted': 0,
        'isWildcard': 0,
        'isRegex': 0,
      });
      await db.insert('block_rule_source', {
        'ruleId': id,
        'source': 'useradd',
        'enabled': 1,
      });
      return id;
    }

    test('loadKind 保留 appScope 与 appInverted', () async {
      await insertScoped('scoped.example', 'com.foo');
      await insertBlock('global.example');

      final rules = await RuleRepository(db).loadKind(RuleKind.block);
      final byPattern = {for (final rule in rules) rule.pattern: rule};

      expect(byPattern['scoped.example']!.appScope, 'com.foo');
      expect(byPattern['global.example']!.appScope, isNull);
    });

    test('loadForApp 只取该应用作用域的规则（含 | 多包名与子串）', () async {
      await insertScoped('a.example', 'com.foo');
      await insertScoped('b.example', 'com.foo|com.bar');
      await insertScoped('c.example', 'com.baz|com.foo');
      await insertScoped('other.example', 'com.qux');
      await insertBlock('global.example');

      final rules = await RuleRepository(db).loadForApp('com.foo');
      final patterns = rules.map((r) => r.pattern).toSet();

      expect(patterns, containsAll(['a.example', 'b.example', 'c.example']));
      expect(patterns, isNot(contains('other.example')));
      expect(patterns, isNot(contains('global.example')));
    });

    test('addForApp 写入 appScope，重复添加返回 null 但复用已有行', () async {
      final repo = RuleRepository(db);
      final created = await repo.addForApp(
        RuleKind.block,
        'ads.example',
        'com.foo',
      );
      expect(created, isNotNull);
      expect(created!.appScope, 'com.foo');

      final again = await repo.addForApp(
        RuleKind.block,
        'ads.example',
        'com.foo',
      );
      expect(again, isNull);
      final rows = await db.query('block_rule');
      expect(rows, hasLength(1));
      expect(rows.single['appScope'], 'com.foo');
    });

    test('setFullBlock 注入/移除 *\$app=<pkg> 且 hasFullBlock 同步', () async {
      final repo = RuleRepository(db);
      expect(await repo.hasFullBlock('com.foo'), isFalse);

      expect(await repo.setFullBlock('com.foo', true), isTrue);
      expect(await repo.hasFullBlock('com.foo'), isTrue);
      final row = (await db.query('block_rule')).single;
      expect(row['pattern'], '*');
      expect(row['appScope'], 'com.foo');

      expect(await repo.setFullBlock('com.foo', false), isFalse);
      expect(await repo.hasFullBlock('com.foo'), isFalse);
      expect(await db.query('block_rule'), isEmpty);
    });
  });
}
