// Rule parsing and import: a semantic drift silently blocks too much or too little, and
// the importer must keep the 1.4.3 `*_rule` / `*_rule_source` contract.

import 'package:diting_android/data/rules/rule_domain_utils.dart';
import 'package:diting_android/data/rules/rule_importer.dart';
import 'package:diting_android/data/rules/rule_models.dart';
import 'package:diting_android/data/rules/rule_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('规则解析', _ruleParser);
  group('规则入库', _ruleImporter);
}

/// Equivalent of 1.4.3's `AdGuardRuleParserTest`: a semantic drift silently blocks too much
/// or too little. The parser is the Rust core now, so these are fixed expectations on its
/// document output; build the library first (`cargo build --release` in `rust/`), exactly like the
/// app needs it.
void _ruleParser() {
  test('域名 / 修饰符 / 放行规则', () {
    final parsed = parseCategorized(
      '||ads.net^\$app=com.app1|com.app2,important\n'
      '@@||*-analytics.google.com^\$app=com.google.android.gms,important\n'
      '||tracker.com^\$app=~com.android.chrome',
    );
    final important = parsed.blockRules.firstWhere(
      (rule) => rule.pattern == 'ads.net',
    );
    expect(important.important, isTrue);
    expect(important.appScope, 'com.app1|com.app2');
    expect(important.appInverted, isFalse);

    final allow = parsed.allowRules.single;
    expect(allow.pattern, '*-analytics.google.com');
    expect(allow.isWildcard, isTrue);
    expect(allow.important, isTrue);
    expect(allow.appScope, 'com.google.android.gms');

    final inverted = parsed.blockRules.firstWhere(
      (rule) => rule.pattern == 'tracker.com',
    );
    expect(inverted.appScope, 'com.android.chrome');
    expect(inverted.appInverted, isTrue);
  });

  test('dnsrewrite：真值变覆写，黑洞变拦截', () {
    final parsed = parseCategorized(
      '||ipv4.com^\$dnsrewrite=1.2.3.4\n'
      '||ipv6.com^\$dnsrewrite=2001:db8::1\n'
      '||cname.com^\$dnsrewrite=target.example.org\n'
      '||blocked.com^\$dnsrewrite=NXDOMAIN\n'
      '||sinkhole.com^\$dnsrewrite=0.0.0.0',
    );
    expect(parsed.rewriteRules.map((rule) => rule.pattern), [
      'ipv4.com',
      'ipv6.com',
      'cname.com',
    ]);
    expect(parsed.rewriteRules.map((rule) => rule.targetType), [
      RewriteTargetType.ipv4,
      RewriteTargetType.ipv6,
      RewriteTargetType.cname,
    ]);
    expect(parsed.rewriteRules.map((rule) => rule.targetValue), [
      '1.2.3.4',
      '2001:db8::1',
      'target.example.org',
    ]);
    expect(parsed.blockRules.map((rule) => rule.pattern), [
      'blocked.com',
      'sinkhole.com',
    ]);
  });

  test('hosts 与 dnsmasq 归类', () {
    final parsed = parseCategorized(
      '0.0.0.0 ads.example.com tracker.example.com # ad hosts\n'
      '1.2.3.4 host1.example.com host2.example.com\n'
      'address=/blocked.com/\n'
      'address=/sink.com/0.0.0.0\n'
      'address=/null.com/#\n'
      'address=/ip.com/10.0.0.3',
    );
    expect(parsed.blockRules.map((rule) => rule.pattern), [
      'ads.example.com',
      'tracker.example.com',
      'blocked.com',
      'sink.com',
      'null.com',
    ]);
    expect(parsed.rewriteRules.map((rule) => rule.pattern), [
      'host1.example.com',
      'host2.example.com',
      'ip.com',
    ]);
  });

  group('整份文本', () {
    test('混合文本按族归类', () {
      // Matches Kotlin's `trimIndent()`: dropped blank lines would add an extra ignored entry
      const text =
          '! Title: Unified List\n'
          '# Comment line\n'
          '[Adblock Plus 2.0]\n'
          'example.com##.ad-banner\n'
          '||ad.com^\n'
          '@@||allow.com^\n'
          r'||rewrite.com^$dnsrewrite=1.2.3.4'
          '\n'
          '0.0.0.0 sink.com\n'
          '10.0.0.2 real.com\n'
          'address=/masq-block.com/\n'
          'address=/masq-ip.com/10.0.0.3';
      final parsed = parseCategorized(text);
      expect(parsed.blockRules.map((rule) => rule.pattern), [
        'ad.com',
        'sink.com',
        'masq-block.com',
      ]);
      expect(parsed.allowRules.map((rule) => rule.pattern), ['allow.com']);
      expect(parsed.rewriteRules.map((rule) => rule.pattern), [
        'rewrite.com',
        'real.com',
        'masq-ip.com',
      ]);
      expect(parsed.cosmeticRules, hasLength(1));
      expect(parsed.ignoredCount, 3);
    });

    test('badfilter 关掉同键规则，且与顺序无关', () {
      const forward = '||example.com^\n||example.com^\$badfilter';
      final a = parseCategorized(forward);
      expect(a.blockRules, isEmpty);
      expect(a.badfilteredCount, 1);

      const reversed = '||example.com^\$badfilter\n||example.com^';
      final b = parseCategorized(reversed);
      expect(b.blockRules, isEmpty);
      expect(b.badfilteredCount, 1);
    });

    test('放行 badfilter 只关放行规则', () {
      const text =
          '||example.com^\n@@||example.com^\n@@||example.com^\$badfilter';
      final parsed = parseCategorized(text);
      expect(parsed.blockRules, hasLength(1));
      expect(parsed.allowRules, isEmpty);
      expect(parsed.badfilteredCount, 1);
    });

    test('重复行计入 duplicate 且只保留一条', () {
      const text = '||dup.com^\n||dup.com^\n||dup.com^';
      final parsed = parseCategorized(text);
      expect(parsed.blockRules, hasLength(1));
      expect(parsed.duplicateCount, 2);
    });
  });

  group('元素隐藏分隔符', () {
    test('#\$@# 例外形式不被降级成整域拦截', () {
      final parsed = parseCategorized('example.com#\$@#.ad-banner');
      expect(parsed.blockRules, isEmpty);
      final rule = parsed.cosmeticRules.single;
      expect(rule.isException, isTrue);
      expect(rule.selector, '.ad-banner');
    });

    test('## / #@# / #?# 都识别为 cosmetic', () {
      final parsed = parseCategorized('a.com##.ad\nb.com#@#.ad\nc.com#?#.ad');
      expect(parsed.cosmeticRules, hasLength(3));
      expect(parsed.blockRules, isEmpty);
    });
  });

  group('域名工具', () {
    test('通配符归一化与 IP 判定', () {
      expect(normalizeWildcardDomain('*'), '*');
      expect(normalizeWildcardDomain('*.Example.COM'), '*.example.com');
      expect(normalizeWildcardDomain('bad domain'), isNull);
      expect(looksLikeLiteralIp('1.2.3.4'), isTrue);
      expect(looksLikeLiteralIp('::1'), isTrue);
      expect(looksLikeLiteralIp('example.com'), isFalse);
      expect(normalizeDomain('Example.COM.'), 'example.com');
      expect(normalizeDomain('1.2.3.4'), isNull);
      expect(normalizeDomain('nodot'), isNull);
    });
  });
}

/// Runs the importer against the real 1.4.3 tables: rules land in `*_rule` with a `sub_<id>`
/// source row, re-imports do not duplicate, and deleting a subscription drops orphan rules
void _ruleImporter() {
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
      'CREATE TABLE go_url_rule (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'pattern TEXT NOT NULL, kind TEXT NOT NULL, rawLine TEXT NOT NULL, '
      'addedAt INTEGER NOT NULL, enabled INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE go_url_rule_source (ruleId INTEGER NOT NULL, source TEXT NOT NULL, '
      'enabled INTEGER NOT NULL, PRIMARY KEY(ruleId, source), '
      'FOREIGN KEY(ruleId) REFERENCES go_url_rule(id) ON DELETE CASCADE)',
    );
    await db.execute(
      'CREATE TABLE subscription (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
      'url TEXT NOT NULL, name TEXT NOT NULL)',
    );
  });

  tearDown(() => db.close());

  Future<int> count(String table) async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table')) ??
      0;

  test('block / allow / rewrite / url 四族分别落到对应表', () async {
    const text =
        '||ads.example.com^\n'
        '@@||safe.example.com^\n'
        '||rewrite.example.com^'
        r'$dnsrewrite=1.2.3.4'
        '\n'
        '||tracker.example.com/pixel.js\n';
    final parsed = parseCategorized(text);
    final importer = RuleImporter(db);

    final summary = await importer.import(
      parsed,
      source: subscriptionSourceTag(7),
      kind: 'domain',
      enabled: true,
    );

    expect(summary.blockCount, 1);
    expect(summary.allowCount, 1);
    expect(summary.rewriteCount, 1);
    expect(summary.urlBlockCount, 1);
    expect(summary.insertedCount, 4);

    expect(await count('block_rule'), 1);
    expect(await count('allow_rule'), 1);
    expect(await count('rewrite_rule'), 1);
    expect(await count('go_url_rule'), 1);

    final sources = await db.query('block_rule_source');
    expect(sources.single['source'], 'sub_7');
    expect(sources.single['enabled'], 1);
  });

  test('重复导入不新增行，只补来源', () async {
    const text = '||dup.example.com^\n||dup.example.com^';
    final parsed = parseCategorized(text);
    final importer = RuleImporter(db);

    final first = await importer.import(
      parsed,
      source: subscriptionSourceTag(1),
      kind: 'domain',
      enabled: true,
    );
    expect(first.blockCount, 1);
    expect(await count('block_rule'), 1);

    final second = await importer.import(
      parsed,
      source: subscriptionSourceTag(1),
      kind: 'domain',
      enabled: true,
    );
    // Same source again: the source row exists, so the insert is ignored.
    expect(second.blockCount, 0);
    expect(await count('block_rule'), 1, reason: '设备库没有唯一索引，必须靠查重复用');

    // Another subscription with the same pattern reuses the rule row.
    final other = await importer.import(
      parsed,
      source: subscriptionSourceTag(2),
      kind: 'domain',
      enabled: true,
    );
    expect(other.blockCount, 1);
    expect(await count('block_rule'), 1);
    expect(await count('block_rule_source'), 2);
  });

  test('删除来源后规则行被清掉，不留孤儿', () async {
    final importer = RuleImporter(db);
    await importer.import(
      parseCategorized('||gone.example.com^'),
      source: subscriptionSourceTag(5),
      kind: 'domain',
      enabled: true,
    );
    expect(await count('block_rule'), 1);

    await importer.removeRulesBySource(subscriptionSourceTag(5));
    expect(await count('block_rule_source'), 0);
    expect(await count('block_rule'), 0, reason: '无来源引用的规则行必须删掉');
  });

  test('孤儿清理按页删除，超过一页也能清空', () async {
    // 一页之外的孤儿行如果没被扫到，就是分批改写引入的静默数据残留。
    final importer = RuleImporter(db);
    final total = RuleImporter.orphanPageSize + 50;
    final lines = [for (var i = 0; i < total; i++) '||bulk$i.example.com^'];
    await importer.import(
      parseCategorized(lines.join('\n')),
      source: subscriptionSourceTag(9),
      kind: 'domain',
      enabled: true,
    );
    expect(await count('block_rule'), total);

    await importer.removeRulesBySource(subscriptionSourceTag(9));
    expect(await count('block_rule_source'), 0);
    expect(await count('block_rule'), 0);
  });

  test('删除一个订阅不影响另一个订阅的同一 pattern', () async {
    final importer = RuleImporter(db);
    const text = '||shared.example.com^';
    await importer.import(
      parseCategorized(text),
      source: subscriptionSourceTag(1),
      kind: 'domain',
      enabled: true,
    );
    await importer.import(
      parseCategorized(text),
      source: subscriptionSourceTag(2),
      kind: 'domain',
      enabled: true,
    );
    expect(await count('block_rule_source'), 2);

    await importer.removeRulesBySource(subscriptionSourceTag(1));
    expect(await count('block_rule'), 1, reason: 'sub_2 还在引用，规则行必须留着');
    expect(await count('block_rule_source'), 1);
  });

  test('cosmetic 解析出来但不入库，并单独计数', () async {
    final parsed = parseCategorized('example.com##.ad-banner');
    final importer = RuleImporter(db);
    final summary = await importer.import(
      parsed,
      source: subscriptionSourceTag(4),
      kind: 'domain',
      enabled: true,
    );
    expect(summary.insertedCount, 0);
    expect(summary.notAppliedCount, 1);
    expect(await count('block_rule'), 0);
  });

  test('带 app 作用域的 URL 规则不入 go_url_rule（该表没有 appScope 列）', () async {
    const text =
        '||ads.example.com/banner.js'
        r'$app=com.foo'
        '\n';
    final parsed = parseCategorized(text);
    expect(parsed.urlBlockRules.single.appScope, 'com.foo');

    final importer = RuleImporter(db);
    final summary = await importer.import(
      parsed,
      source: subscriptionSourceTag(12),
      kind: 'domain',
      enabled: true,
    );
    // Dropping the scope would turn it into a global URL block, so skip the rule.
    expect(summary.urlBlockCount, 0);
    expect(await count('go_url_rule'), 0);
  });
}
