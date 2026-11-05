// The Rust rule core must classify every line exactly like the Dart implementation. Skipped when
// the native library was never built; build it with `cargo build --release` in `rust/` first, or
// `python rust/build_android.py` for the APK artifact.

import 'dart:math';

import 'package:diting_android/data/rules/rule_models.dart';
import 'package:diting_android/data/rules/rule_parser.dart';
import 'package:diting_android/data/rules/rust_rule_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lines that pin down every branch of the parser: comments, cosmetic delimiters, URL and regex
/// forms, modifier families, hosts, dnsmasq and the awkward shapes around them.
const _corpus = <String>[
  '! Title: test list',
  '# comment line',
  '[Adblock Plus 2.0]',
  r'||example.com^',
  r'||example.com^$important',
  r'||ads.net^$app=com.app1|com.app2,important',
  r'||tracker.com^$app=~com.android.chrome',
  r'||*-analytics.google.com^$app=com.google.android.gms',
  r'||safe.example.com^',
  r'@@||safe.example.com^',
  '@@',
  r'@@||a.com^$badfilter',
  r'||a.com^$badfilter',
  r'||example.com^$denyallow=a.com|b.com',
  r'||example.com^$denyallow=',
  r'||example.com^$~denyallow=a.com',
  r'||example.com^$denyallow=||a.com^|b.com.',
  r'||example.com^$dnstype=A|AAAA',
  r'||example.com^$~dnstype=A',
  r'||example.com^$dnstype=FOO',
  r'||example.com^$dnstype=',
  r'||example.com^$dnsrewrite=1.2.3.4',
  r'||example.com^$dnsrewrite=2001:db8::1',
  r'||example.com^$dnsrewrite=target.example.org',
  r'||example.com^$dnsrewrite=NXDOMAIN',
  r'||example.com^$dnsrewrite=nxdomain',
  r'||example.com^$dnsrewrite=REFUSED',
  r'||example.com^$dnsrewrite=SERVFAIL',
  r'||example.com^$dnsrewrite=0.0.0.0',
  r'||example.com^$dnsrewrite=::1',
  r'||example.com^$dnsrewrite=REFUSED;8.8.8.8',
  r'||example.com^$dnsrewrite=8.8.8.8;',
  r'||example.com^$dnsrewrite=a.example.com;b.example.com',
  r'||example.com^$dnsrewrite=',
  r'||example.com^$badfilter,dnsrewrite=1.2.3.4',
  r'||example.com^$image,third-party',
  r'||example.com^$removeparam=utm_source',
  r'||example.com/banner.js$script,badfilter',
  r'||example.com^$all',
  r'||example.com^$all,important',
  r'||example.com^$foo=bar',
  r'||example.com^$',
  r'||example.com^$important,',
  r'||example.com^$app=',
  r'||example.com^$app=~',
  r'||example.com^$important,important',
  r'/^ad[0-9]+\.example\.com$/',
  r'@@/^safe[0-9]+\.blocked\.com$/',
  r'/^ad[0-9]+\.example\.com$/$important',
  '/invalid(regex/',
  '/(/',
  '/)/',
  '/a**/',
  '/a{2}/',
  '/a{2,}/',
  '/a{2,4}/',
  '/a??/',
  '/(?:a|b)+/',
  '/[/',
  r'/a\/',
  '//',
  '/a/',
  '/a/b',
  '|http://example.com^',
  '|https://example.com/ad^',
  '||example.com/path^',
  '||*/path^',
  '*/ad/path',
  '/ads/banner.js',
  'example.com##.ad-banner',
  'example.com#@#.ad',
  'example.com#?#.ad',
  r'example.com#$#.ad { color: red }',
  r'example.com#$@#.ad-banner',
  '##.generic-ad',
  'a.com,b.com##.ad',
  'example.com##',
  '0.0.0.0 ads.example.com tracker.example.com # hosts comment',
  '127.0.0.1 local.example.com',
  '::1 v6.example.com',
  '1.2.3.4 host1.example.com host2.example.com',
  '10.0.0.2 real.com',
  '10.0.0.2 bad_host.com',
  'address=/blocked.com/',
  'address=/sink.com/0.0.0.0',
  'address=/null.com/#',
  'server=/a.example.com/1.2.3.4',
  'address=/a.example.com/b.example.com',
  'address=/a.example.com/1.2.3.4.5',
  'address=/',
  'server=/',
  'address=/a.com/b.com/ # dnsmasq comment',
  'address=/a.com/b.com/\t# tab comment',
  'address=/a.com, b.com/1.2.3.4',
  'address=/a.com/#',
  'address=/*.wild.com/',
  r'||example.com^ # trailing comment',
  '||example.com#comment',
  '||exa#mple.com^',
  '||example.com//#comment',
  r'||example.com^ $important',
  r'||example.com^$important # comment',
  '',
  '   ',
  '\uFEFF||bom.example.com^',
  '||UPPER.Case.COM^',
  '||中文.cn^',
  '||éxample.com^',
  '||a.com#é',
  '||a.com?é',
  '||a_b.com^',
  '||*.wild.com^',
  '||*^',
  '||^',
  '||',
  '@@||',
  '||localhost^',
  '||127.0.0.1^',
  '||a.com.^',
  '||a..com^',
  '||xn--fiq228c.cn^',
  '||example.com^^^^',
  '||example.com*^',
  '0.0.0.0',
  '0.0.0.0 # only a comment',
  '1.2.3.4',
  '::',
  '0',
  '0 a.com',
  '-1.example.com',
  r'||a.com^$app=com.a|~com.b',
  r'||a.com^$app=~com.a|com.b',
  r'||a.com^$dnstype=~A',
  r'||a.com^$denyallow=~a.com',
  r'||a.com^$dnsrewrite=NXDOMAIN;1.2.3.4',
  'example.com##div:has(> .ad)',
  '!.',
  r'@@||allow.com^$important',
  '||a.com^\t# tabbed comment',
];

/// Canonical, comparable rendering of a parse result: order, family and every field.
List<String> _render(CategorizedRules rules) => [
  'stats: total=${rules.totalLines} dup=${rules.duplicateCount} '
      'invalid=${rules.invalidCount} unsupported=${rules.unsupportedCount} '
      'ignored=${rules.ignoredCount} badfiltered=${rules.badfilteredCount}',
  for (final rule in rules.blockRules)
    'block|${rule.pattern}|${rule.rawLine}|${rule.important}|${rule.appScope}|'
        '${rule.appInverted}|${rule.isWildcard}|${rule.denyallow}|${rule.isRegex}|${rule.dnsType}',
  for (final rule in rules.allowRules)
    'allow|${rule.pattern}|${rule.rawLine}|${rule.important}|${rule.appScope}|'
        '${rule.appInverted}|${rule.isWildcard}|${rule.denyallow}|${rule.isRegex}|${rule.dnsType}',
  for (final rule in rules.rewriteRules)
    'rewrite|${rule.pattern}|${rule.targetType}|${rule.targetValue}|${rule.rawLine}',
  for (final rule in rules.urlBlockRules)
    'urlBlock|${rule.pattern}|${rule.rawLine}|${rule.isAllow}|${rule.appScope}|${rule.important}',
  for (final rule in rules.urlAllowRules)
    'urlAllow|${rule.pattern}|${rule.rawLine}|${rule.isAllow}|${rule.appScope}|${rule.important}',
  for (final rule in rules.cosmeticRules)
    'cosmetic|${rule.domain}|${rule.selector}|${rule.rawLine}|${rule.isException}',
];

void main() {
  final core = RustRuleCore.instance;
  final skipReason = core == null
      ? 'Rust 库未构建：先在 rust/ 下执行 cargo build --release'
      : null;

  group('Rust 规则内核', () {
    test('原生库可加载且 ABI 匹配', () {
      expect(core, isNotNull, reason: skipReason);
      expect(core!.libraryPath, isNotEmpty);
    }, skip: skipReason);

    test('逐行语义与 Dart 实现一致', () {
      final mismatches = <String>[];
      for (final line in _corpus) {
        final expected = _render(parseCategorizedInDart(line));
        final actual = _render(core!.tryParse(line)!);
        if (!_sameList(expected, actual)) {
          mismatches.add('line: $line\n  dart: $expected\n  rust: $actual');
        }
      }
      expect(mismatches, isEmpty, reason: mismatches.join('\n'));
    }, skip: skipReason);

    test('整份文本的归类、去重与 badfilter 一致', () {
      final text = _corpus.join('\n');
      expect(_render(core!.tryParse(text)!), _render(parseCategorizedInDart(text)));
    }, skip: skipReason);

    test('生成的大列表与 Dart 实现一致', () {
      final text = _syntheticList(4000);
      expect(_render(core!.tryParse(text)!), _render(parseCategorizedInDart(text)));
    }, skip: skipReason);

    test('随机拼接行的语义与 Dart 实现一致', () {
      final random = Random(20251105);
      final mismatches = <String>[];
      for (var index = 0; index < 6000; index++) {
        final line = _randomLine(random);
        final expected = _render(parseCategorizedInDart(line));
        final actual = _render(core!.tryParse(line)!);
        if (!_sameList(expected, actual)) {
          mismatches.add('line: $line\n  dart: $expected\n  rust: $actual');
        }
      }
      expect(mismatches, isEmpty, reason: mismatches.join('\n'));
    }, skip: skipReason);
  });
}

const _lineStarts = ['', '@@', '||', '|', '*/', '/', '0.0.0.0 ', '1.2.3.4 ', '::1 ', '#', '!', '@@|'];

const _lineCores = [
  'example.com',
  'a.example.com',
  'A.Example.COM.',
  '*.wild.com',
  '*',
  'a..com',
  '.a.com',
  '-a.com',
  'a-.com',
  'a_b.com',
  '127.0.0.1',
  '1.2.3.4.5',
  '::1',
  '2001:DB8::1',
  '中文.cn',
  'éxample.com',
  'xn--fiq228c.cn',
  'a b.com',
  'a.com/path',
  'example.com##.ad',
  'example.com#@#.ad',
  r'example.com#$@#.ad',
  'address=/a.com/',
  'server=/a.com/1.2.3.4',
  'address=/a.com/b.com',
  'address=/a.com/#',
  '/re[0-9]+/',
  '/(/',
  '',
  '^',
  'localhost',
];

const _lineEnds = ['', '^', '^^', '|', '*', '.', '#cmt', ' #cmt', '\t#cmt', '####'];

const _lineModifiers = [
  '',
  r'$important',
  r'$app=com.a',
  r'$app=~com.a|com.b',
  r'$denyallow=a.com|b.com',
  r'$dnstype=A',
  r'$~dnstype=A|AAAA',
  r'$dnsrewrite=1.2.3.4',
  r'$dnsrewrite=NXDOMAIN',
  r'$dnsrewrite=c.example.com',
  r'$dnsrewrite=0.0.0.0',
  r'$badfilter',
  r'$third-party',
  r'$foo=bar',
  r'$',
  r'$,important',
  r'$all,image',
  r'$important,important',
];

String _randomLine(Random random) {
  String pick(List<String> values) => values[random.nextInt(values.length)];
  return '${pick(_lineStarts)}${pick(_lineCores)}${pick(_lineEnds)}'
      '${pick(_lineModifiers)}';
}

bool _sameList(List<String> expected, List<String> actual) {
  if (expected.length != actual.length) return false;
  for (var index = 0; index < expected.length; index++) {
    if (expected[index] != actual[index]) return false;
  }
  return true;
}

/// A list shaped like a real subscription: mostly domain rules, plus hosts, cosmetic, regex and
/// duplicated lines so the counters are exercised too.
String _syntheticList(int count) {
  final buffer = StringBuffer();
  for (var index = 0; index < count; index++) {
    switch (index % 8) {
      case 0:
        buffer.writeln('||ads$index.example.com^');
      case 1:
        buffer.writeln('0.0.0.0 tracker$index.example.net');
      case 2:
        buffer.writeln('example$index.org##.ad-banner');
      case 3:
        buffer.writeln('@@||safe$index.example.com^\$app=com.a|com.b');
      case 4:
        buffer.writeln('/^ad[0-9]+$index\\.example\\.com\$/');
      case 5:
        buffer.writeln('address=/masq$index.example.com/');
      case 6:
        buffer.writeln('||ads${index - 6}.example.com^');
      default:
        buffer.writeln('! comment $index');
    }
  }
  return buffer.toString();
}
