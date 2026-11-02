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
/// or too little
void _ruleParser() {
  group('域名 / 修饰符', () {
    test('标准拦截规则与修饰符', () {
      final standard = parseRule('||example.com^');
      expect(standard, isNotNull);
      expect(standard!.pattern, 'example.com');
      expect(standard.important, isFalse);
      expect(standard.appScope, isNull);

      final appImportant = parseRule(
        '||ads.net^\$app=com.app1|com.app2,important',
      );
      expect(appImportant, isNotNull);
      expect(appImportant!.pattern, 'ads.net');
      expect(appImportant.important, isTrue);
      expect(appImportant.appScope, 'com.app1|com.app2');
      expect(appImportant.appInverted, isFalse);

      final inverted = parseRule('||tracker.com^\$app=~com.android.chrome');
      expect(inverted, isNotNull);
      expect(inverted!.pattern, 'tracker.com');
      expect(inverted.appScope, 'com.android.chrome');
      expect(inverted.appInverted, isTrue);

      final wildcard = parseRule(
        '||*-analytics.google.com^\$app=com.google.android.gms',
      );
      expect(wildcard, isNotNull);
      expect(wildcard!.pattern, '*-analytics.google.com');
      expect(wildcard.isWildcard, isTrue);
    });

    test('放行规则与修饰符', () {
      final allow = parseAllowRule(
        '@@||*-analytics.google.com^\$app=com.google.android.gms,important',
      );
      expect(allow, isNotNull);
      expect(allow!.pattern, '*-analytics.google.com');
      expect(allow.isWildcard, isTrue);
      expect(allow.important, isTrue);
      expect(allow.appScope, 'com.google.android.gms');
    });

    test('\$all 与 \$all,important', () {
      expect(parseRule('||example.com^\$all')!.pattern, 'example.com');
      expect(parseRule('||example.com^\$all,important')!.important, isTrue);
    });

    test('只对 HTTP 有意义的修饰符整行忽略', () {
      expect(
        parseCategorizedLine('||example.com^\$image,third-party').ignoredCount,
        1,
      );
      expect(
        parseCategorizedLine('||example.com^\$removeparam=utm_source')
            .ignoredCount,
        1,
      );
      expect(
        parseCategorizedLine('||example.com/banner.js\$script,badfilter')
            .ignoredCount,
        1,
      );
    });
  });

  group('dnsrewrite', () {
    test('IPv4 / IPv6 / CNAME 三种目标', () {
      final ipv4 = parseCategorizedLine('||example.com^\$dnsrewrite=1.2.3.4');
      expect(ipv4.rewriteRules, hasLength(1));
      expect(ipv4.rewriteRules.first.pattern, 'example.com');
      expect(ipv4.rewriteRules.first.targetType, RewriteTargetType.ipv4);
      expect(ipv4.rewriteRules.first.targetValue, '1.2.3.4');

      final ipv6 = parseCategorizedLine('||ipv6.com^\$dnsrewrite=2001:db8::1');
      expect(ipv6.rewriteRules, hasLength(1));
      expect(ipv6.rewriteRules.first.targetType, RewriteTargetType.ipv6);
      expect(ipv6.rewriteRules.first.targetValue, '2001:db8::1');

      final cname = parseCategorizedLine(
        '||cname.com^\$dnsrewrite=target.example.org',
      );
      expect(cname.rewriteRules, hasLength(1));
      expect(cname.rewriteRules.first.targetType, RewriteTargetType.cname);
      expect(cname.rewriteRules.first.targetValue, 'target.example.org');
    });

    test('NXDOMAIN 与黑洞地址变成拦截规则', () {
      final nx = parseCategorizedLine('||blocked.com^\$dnsrewrite=NXDOMAIN');
      expect(nx.blockRules, hasLength(1));
      expect(nx.blockRules.first.pattern, 'blocked.com');

      final zero = parseCategorizedLine('||sinkhole.com^\$dnsrewrite=0.0.0.0');
      expect(zero.blockRules, hasLength(1));
      expect(zero.blockRules.first.pattern, 'sinkhole.com');
    });
  });

  group('hosts 与 dnsmasq', () {
    test('黑洞 hosts 一行多域名展开成多条拦截', () {
      final sinkhole = parseCategorizedLine(
        '0.0.0.0 ads.example.com tracker.example.com # ad hosts',
      );
      expect(sinkhole.blockRules, hasLength(2));
      expect(sinkhole.blockRules[0].pattern, 'ads.example.com');
      expect(sinkhole.blockRules[1].pattern, 'tracker.example.com');
      expect(sinkhole.rewriteRules, isEmpty);
    });

    test('真实 IP 的 hosts 行变成覆写', () {
      final realIp = parseCategorizedLine(
        '1.2.3.4 host1.example.com host2.example.com',
      );
      expect(realIp.blockRules, isEmpty);
      expect(realIp.rewriteRules, hasLength(2));
      expect(realIp.rewriteRules[0].pattern, 'host1.example.com');
      expect(realIp.rewriteRules[0].targetValue, '1.2.3.4');
      expect(realIp.rewriteRules[1].pattern, 'host2.example.com');
    });

    test('dnsmasq 黑洞三种写法都算拦截', () {
      for (final line in [
        'address=/blocked.com/',
        'address=/sink.com/0.0.0.0',
        'address=/null.com/#',
      ]) {
        final parsed = parseCategorizedLine(line);
        expect(parsed.blockRules, hasLength(1), reason: line);
        expect(parsed.rewriteRules, isEmpty, reason: line);
      }
    });
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
      expect(parsed.blockRules.map((r) => r.pattern), [
        'ad.com',
        'sink.com',
        'masq-block.com',
      ]);
      expect(parsed.allowRules.map((r) => r.pattern), ['allow.com']);
      expect(parsed.rewriteRules.map((r) => r.pattern), [
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
      final line = parseCategorizedLine('example.com#\$@#.ad-banner');
      expect(line.blockRules, isEmpty);
      expect(line.cosmeticRules, hasLength(1));
      expect(line.cosmeticRules.first.isException, isTrue);
      expect(line.cosmeticRules.first.selector, '.ad-banner');
    });

    test('## / #@# / #?# 都识别为 cosmetic', () {
      for (final line in [
        'example.com##.ad',
        'example.com#@#.ad',
        'example.com#?#.ad',
      ]) {
        final parsed = parseCategorizedLine(line);
        expect(parsed.cosmeticRules, hasLength(1), reason: line);
        expect(parsed.blockRules, isEmpty, reason: line);
      }
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
