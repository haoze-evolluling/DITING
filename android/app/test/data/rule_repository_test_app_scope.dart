part of 'rule_repository_test.dart';

void _appScopedRules() {
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
      'enabled INTEGER NOT NULL, PRIMARY KEY(ruleId, source))',
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
      'enabled INTEGER NOT NULL, PRIMARY KEY(ruleId, source))',
    );
    await db.execute(
      'CREATE TABLE rewrite_rule (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'pattern TEXT NOT NULL, targetType TEXT NOT NULL, targetValue TEXT NOT NULL, '
      'rawLine TEXT NOT NULL, addedAt INTEGER NOT NULL, enabled INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE rewrite_rule_source (ruleId INTEGER NOT NULL, source TEXT NOT NULL, '
      'enabled INTEGER NOT NULL, PRIMARY KEY(ruleId, source))',
    );
    await db.execute(
      'CREATE TABLE subscription (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'name TEXT NOT NULL)',
    );
    await db.execute('PRAGMA foreign_keys = ON');
  });

  tearDown(() => db.close());

  Future<void> insertBlock(String pattern, String appScope) async {
    final id = await db.insert('block_rule', {
      'pattern': pattern,
      'rawLine': pattern,
      'addedAt': 1,
      'enabled': 1,
      'important': 0,
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
  }

  Future<void> insertAllow(String pattern, String appScope) async {
    final id = await db.insert('allow_rule', {
      'pattern': pattern,
      'rawLine': pattern,
      'addedAt': 1,
      'enabled': 1,
      'important': 0,
      'appScope': appScope,
      'appInverted': 0,
      'isWildcard': 0,
      'isRegex': 0,
    });
    await db.insert('allow_rule_source', {
      'ruleId': id,
      'source': 'useradd',
      'enabled': 1,
    });
  }

  ProviderContainer containerWith(RuleRepository? repository) {
    final container = ProviderContainer(
      overrides: [ruleRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('规则库不可用时如实返回 unavailable', () async {
    final container = containerWith(null);
    final rules = await container.read(
      appScopedRulesProvider('com.foo').future,
    );
    expect(rules.available, isFalse);
    expect(rules.error, isNotNull);
  });

  test('按应用分类 black/allow 并读出 fullBlock', () async {
    await insertBlock('ads.example', 'com.foo');
    await insertAllow('cdn.example', 'com.foo');
    await insertBlock('other.example', 'com.bar');

    final repo = RuleRepository(db);
    final container = containerWith(repo);
    final rules = await container.read(
      appScopedRulesProvider('com.foo').future,
    );

    expect(rules.available, isTrue);
    expect(rules.block.map((r) => r.pattern), ['ads.example']);
    expect(rules.allow.map((r) => r.pattern), ['cdn.example']);
    expect(rules.fullBlock, isFalse);
  });

  test('全局规则页不展示带 appScope 的规则', () {
    // RulesNotifier must drop app-scoped rules, or the blacklist treats an app rule as global
    final container = ProviderContainer(
      overrides: [
        initialRulesProvider.overrideWith(
          () => _ScopedInitialRules({
            RuleKind.block: const [
              MockRule(
                id: '1',
                pattern: 'global.example',
                kind: RuleKind.block,
                source: RuleSource.user,
              ),
              MockRule(
                id: '2',
                pattern: 'scoped.example',
                kind: RuleKind.block,
                source: RuleSource.user,
                appScope: 'com.foo',
              ),
            ],
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    final rules = container.read(rulesProvider);
    expect(rules[RuleKind.block]!.map((r) => r.pattern), ['global.example']);
  });
}

// Data-layer behavior of app-scoped rules: providers classify results, reporting "unavailable" not
// empty

/// Fixed state for one-shot override of the initial-rules provider.
class _ScopedInitialRules extends InitialRulesNotifier {
  _ScopedInitialRules(this._initial);

  final Map<RuleKind, List<MockRule>> _initial;

  @override
  Map<RuleKind, List<MockRule>> build() => _initial;
}
