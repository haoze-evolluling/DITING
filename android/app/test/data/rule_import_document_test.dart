import 'dart:io';

import 'package:diting_android/data/db/database_schema.dart';
import 'package:diting_android/data/db/rule_version_repository.dart';
import 'package:diting_android/data/db/storage_contract.dart';
import 'package:diting_android/data/rules/rule_importer.dart';
import 'package:diting_android/data/rules/rule_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late Database db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rule-import-');
    db = await databaseFactory.openDatabase('${dir.path}/rules.db');
    for (final statement in DatabaseSchema.statementsFor(
      DatabaseKind.normalRules,
    )) {
      await db.execute(statement);
    }
    await db.insert('subscription', {
      'id': 1,
      'url': 'https://example.com/rules.txt',
      'name': '示例订阅',
      'sourceType': 'remote',
      'kind': 'domain',
      'enabled': 1,
      'ruleCount': 0,
      'lastUpdated': 0,
      'addedAt': 1,
      'importState': 'importing',
      'lastAttemptAt': 0,
      'consecutiveFailureCount': 0,
      'mirrorFallback': 1,
      'groupId': null,
    });
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  const document =
      '! 头部注释\n'
      '||a.example.com^\n'
      '||b.example.com^\n'
      '||a.example.com^\n'
      '@@||allow.example.com^\n'
      '||rw.example.com^\$dnsrewrite=1.2.3.4\n'
      '||cdn.example.com/ads.js\n'
      'invalid line without meaning\n';

  Future<RuleDocumentImport> importText({
    String? knownHash,
    int maxVersionRules = 60000,
  }) => RuleImporter(db).importDocument(
    document,
    source: 'sub_1',
    staging: 'staging_sub_1',
    kind: 'domain',
    enabled: true,
    subscriptionId: 1,
    knownHash: knownHash,
    now: 1,
    maxVersionRules: maxVersionRules,
  );

  test('原文直通导入写库，统计与规则集哈希和解析结果一致', () async {
    final result = await importText();
    expect(result.unchanged, isFalse);
    expect(result.deleted, isFalse);
    expect(result.summary.blockCount, 2);
    expect(result.summary.allowCount, 1);
    expect(result.summary.rewriteCount, 1);
    expect(result.summary.urlBlockCount, 1);
    expect(result.summary.duplicateCount, 1);

    final parsed = parseCategorized(document);
    final expectedHash = ruleSetHash(canonicalRules(parsed));
    expect(result.hash, expectedHash);
    expect(result.versionRules, canonicalRules(parsed));

    final blocks = await db.query('block_rule', orderBy: 'pattern');
    expect(blocks.map((row) => row['pattern']), [
      'a.example.com',
      'b.example.com',
    ]);
    final sources = await db.query('block_rule_source');
    expect(sources, hasLength(2));
    expect(sources.every((row) => row['source'] == 'sub_1'), isTrue);
    expect(await db.query('allow_rule'), hasLength(1));
    expect(await db.query('rewrite_rule'), hasLength(1));
    expect(await db.query('go_url_rule'), hasLength(1));
    expect(await db.query('cosmetic_rule'), isEmpty);
  });

  test('哈希一致时跳过写库，已提交的规则保持不变', () async {
    final first = await importText();
    expect(first.summary.insertedCount, greaterThan(0));
    final before = await db.query('block_rule');

    final again = await importText(knownHash: first.hash);
    expect(again.unchanged, isTrue);
    expect(again.deleted, isFalse);
    expect(again.summary.insertedCount, 0);
    expect(await db.query('block_rule'), hasLength(before.length));
  });

  test('订阅在导入期间被删除时回滚且不写库', () async {
    await db.delete('subscription', where: 'id = 1');
    final result = await importText();
    expect(result.deleted, isTrue);
    expect(await db.query('block_rule'), isEmpty);
    expect(await db.query('block_rule_source'), isEmpty);
  });

  test('超大文档不记录版本快照', () async {
    final lines = [for (var i = 0; i < 5000; i++) '||h$i.example.com^'];
    final result = await RuleImporter(db).importDocument(
      lines.join('\n'),
      source: 'sub_1',
      staging: 'staging_sub_1',
      kind: 'domain',
      enabled: true,
      subscriptionId: 1,
      knownHash: null,
      now: 1,
      maxVersionRules: 100,
    );
    expect(result.versionSkipped, isTrue);
    expect(result.versionRules, isEmpty);
    expect(result.summary.blockCount, 5000);
  });
}
