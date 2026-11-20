import 'dart:typed_data';

import 'package:diting_android/data/rules/rule_models.dart';
import 'package:diting_android/data/rules/rule_parser.dart';
import 'package:diting_android/data/rules/rust_rule_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('单块流式解析与整份解析一致', () {
    const text =
        '||a.example.com^\n'
        '@@||b.example.com^\n'
        '||c.example.com^\$dnsrewrite=1.2.3.4\n'
        '||d.example.com/pixel.js\n'
        'e.com##.ad\n'
        '||a.example.com^\n'
        '! comment\n';
    final whole = parseCategorized(text);
    final streamed = _drain(streamParseCategorized(text));

    expect(_sorted(streamed.block), _sorted(_patterns(whole.blockRules)));
    expect(_sorted(streamed.allow), _sorted(_patterns(whole.allowRules)));
    expect(streamed.rewrite.length, whole.rewriteRules.length);
    expect(streamed.url.length, whole.urlBlockRules.length);
    expect(streamed.cosmetic.length, whole.cosmeticRules.length);
    expect(streamed.duplicate, whole.duplicateCount);
    expect(streamed.totalLines, whole.totalLines);
  });

  test('跨块的 \$badfilter 仍会移除前面块里的规则，结果集合与整份解析一致', () {
    final lines = <String>['||ads.example.com^'];
    for (var i = 0; i < 2500; i++) {
      lines.add('||host$i.example.com^');
    }
    lines.add('||ads.example.com^\$badfilter');
    final text = lines.join('\n');

    final whole = parseCategorized(text);
    final streamed = _drain(streamParseCategorized(text));

    final streamedBlock = _sorted(streamed.block);
    expect(streamedBlock, _sorted(_patterns(whole.blockRules)));
    expect(streamedBlock.contains('ads.example.com'), isFalse);
  });

  test('原始字节入口与文本入口结果一致', () {
    const text = '||a.example.com^\n@@||b.example.com^\n';
    final fromText = _drain(streamParseCategorized(text));
    final fromBytes = _drain(streamParseCategorizedBytes(_utf8(text)));
    expect(_sorted(fromBytes.block), _sorted(fromText.block));
    expect(_sorted(fromBytes.allow), _sorted(fromText.allow));
  });
}

({List<String> block, List<String> allow, List<String> rewrite, List<String> url,
    List<String> cosmetic, int duplicate, int totalLines}) _drain(
  RuleStreamParse stream,
) {
  final block = <String>[];
  final allow = <String>[];
  final rewrite = <String>[];
  final url = <String>[];
  final cosmetic = <String>[];
  var duplicate = 0;
  var totalLines = 0;
  try {
    for (var chunk = stream.next(); chunk != null; chunk = stream.next()) {
      block.addAll(_patterns(chunk.blockRules));
      allow.addAll(_patterns(chunk.allowRules));
      rewrite.addAll([for (final rule in chunk.rewriteRules) rule.pattern]);
      url.addAll([for (final rule in chunk.urlBlockRules) rule.pattern]);
      cosmetic.addAll([for (final rule in chunk.cosmeticRules) rule.selector]);
      duplicate += chunk.duplicateCount;
      totalLines += chunk.totalLines;
    }
  } finally {
    stream.dispose();
  }
  return (
    block: block,
    allow: allow,
    rewrite: rewrite,
    url: url,
    cosmetic: cosmetic,
    duplicate: duplicate,
    totalLines: totalLines,
  );
}

List<String> _patterns(List<ParsedRule> rules) => [
  for (final rule in rules) rule.pattern,
];

List<String> _sorted(List<String> values) => values..sort();

Uint8List _utf8(String text) => Uint8List.fromList([for (final unit in text.codeUnits) unit]);
