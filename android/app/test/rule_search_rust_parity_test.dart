// The native rule search must return exactly the rows the Dart filter returns. Skipped when the
// native library was never built; build it with `cargo build --release` in `rust/` first, or
// `python rust/build_android.py` for the APK artifact.

import 'dart:math';

import 'package:diting_android/data/db/rule_providers.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/data/rules/rule_search_index.dart';
import 'package:diting_android/data/rules/rust_rule_core.dart';
import 'package:diting_android/state/rules_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rows shaped like the three rule tables, including the awkward case-folding corners the Rust
/// port pins (`search.rs`): a final sigma, the dotted I, and two blocks Dart's tables never mapped.
const _corpus = <RuleSearchEntry>[
  (pattern: '||ads.example.com^', target: null),
  (pattern: '||ads.example.net^', target: null),
  (pattern: '||tracker.example.com^', target: '0.0.0.0'),
  (pattern: '||safe.example.org^', target: '1.1.1.1'),
  (pattern: 'example.com##.ad-banner', target: null),
  (pattern: r'||ads.example.com^$app=com.android.chrome', target: null),
  (pattern: '0.0.0.0 ads.example.local', target: null),
  (pattern: '||ÄPFEL.example.com^', target: null),
  (pattern: '||ähnlich.example.de^', target: null),
  (pattern: '||ΑΣ.example.gr^', target: null),
  (pattern: '||İstanbul.example.tr^', target: null),
  (pattern: '||ẞtraße.example.de^', target: null),
  (pattern: '||ǅungla.example.ba^', target: null),
  (pattern: '||Ⅰ.example.unicode^', target: null),
  (pattern: '||\u{104B0}deseret.example.com^', target: null),
  (pattern: '||\u{13A0}cherokee.example.com^', target: null),
];

const _queries = <String>[
  '',
  'ads',
  'ADS',
  'example',
  '0.0.0.0',
  '1.1.1.1',
  'chrome',
  r'.com^$app',
  'äpfel',
  'ÄPFEL',
  'ähn',
  'ασ',
  'ΑΣ',
  'istanbul',
  'İSTANBUL',
  'straße',
  'ẞTRASSE',
  'ǆ',
  'ǅ',
  'ⅰ',
  'Ⅰ',
  '\u{104B0}',
  '\u{104D8}',
  '\u{13A0}',
  'nothing-here',
];

/// The implementation the page used before the migration: fold every row on every keystroke.
List<int> _dartMatches(List<RuleSearchEntry> rows, String query) {
  final needle = query.toLowerCase();
  return [
    for (var index = 0; index < rows.length; index++)
      if (rows[index].pattern.toLowerCase().contains(needle) ||
          (rows[index].target?.toLowerCase().contains(needle) ?? false))
        index,
  ];
}

void main() {
  final core = RustRuleCore.instance;
  final skipReason = core == null
      ? 'Rust 规则内核未构建：在 rust/ 里跑 cargo build --release'
      : !core.supportsSearch
      ? '库 ${core.libraryPath} 没有检索符号（旧的 .so）'
      : null;

  group('规则检索 Rust 对拍', () {
    test('语料逐条与 Dart 实现一致', () {
      final index = RuleSearchIndex(() => _corpus);
      addTearDown(index.dispose);
      for (final query in _queries) {
        expect(
          index.match(query),
          _dartMatches(_corpus, query),
          reason: 'query "$query"',
        );
      }
    }, skip: skipReason);

    test('大小写和非 ASCII 折叠与 Dart 一致', () {
      final index = RuleSearchIndex(() => _corpus);
      addTearDown(index.dispose);
      // U+0130 loses its combining dot in Dart, and the Greek sigma is folded context free.
      expect(_corpus[index.match('İSTANBUL')!.single].pattern, contains('İstanbul'));
      expect(_corpus[index.match('ΑΣ')!.single].pattern, contains('ΑΣ'));
      expect(index.match('İ'), _dartMatches(_corpus, 'İ'));
      expect(index.match('Σ'), _dartMatches(_corpus, 'Σ'));
    }, skip: skipReason);

    test('随机表与随机查询与 Dart 实现一致', () {
      final random = Random(7);
      final rows = <RuleSearchEntry>[
        for (var index = 0; index < 2000; index++)
          (
            pattern: _randomPattern(random, index),
            target: index % 5 == 0 ? '10.0.${index % 256}.1' : null,
          ),
      ];
      final index = RuleSearchIndex(() => rows);
      addTearDown(index.dispose);
      for (var round = 0; round < 120; round++) {
        final query = _randomQuery(random);
        expect(
          index.match(query),
          _dartMatches(rows, query),
          reason: 'query "$query"',
        );
      }
    }, skip: skipReason);

    test('同一索引连续查询互不影响', () {
      final index = RuleSearchIndex(() => _corpus);
      addTearDown(index.dispose);
      final first = index.match('ads');
      index.match('example');
      expect(index.match('ads'), first);
    }, skip: skipReason);
  });

  group('规则页过滤', () {
    test('空查询只按来源筛选，键入查询后与 Dart 过滤一致', () {
      final container = ProviderContainer(
        overrides: [
          initialRulesProvider.overrideWith(
            () => _FixedInitialRules({RuleKind.block: _rows}),
          ),
        ],
      );
      addTearDown(container.dispose);

      for (final source in <RuleSource?>[null, RuleSource.user]) {
        final all = container.read(
          filteredRulesProvider(
            RuleListFilter(kind: RuleKind.block, source: source),
          ),
        );
        expect(
          all.map((rule) => rule.id),
          _expectedIds(source: source, query: ''),
          reason: 'empty query, source $source',
        );
      }

      for (final query in ['ads', 'EXAMPLE', '0.0.0.0', 'nothing']) {
        final visible = container.read(
          filteredRulesProvider(
            RuleListFilter(kind: RuleKind.block, query: query),
          ),
        );
        expect(
          visible.map((rule) => rule.id),
          _expectedIds(source: null, query: query),
          reason: 'query "$query"',
        );
      }
    });
  });
}

String _randomPattern(Random random, int index) {
  const prefixes = <String>['||', '@@||', '0.0.0.0 ', 'example.com##.'];
  const bodies = <String>[
    'ads',
    'tracker',
    'safe',
    'analytics',
    'metric',
    'ΑΣ',
    'ÄPFEL',
    'İstanbul',
  ];
  final prefix = prefixes[random.nextInt(prefixes.length)];
  final body = bodies[random.nextInt(bodies.length)];
  return '$prefix$body$index.example.com^';
}

String _randomQuery(Random random) {
  const needles = <String>[
    'ads',
    'ADS',
    'track',
    'example',
    '.com^',
    'ασ',
    'ΑΣ',
    'äpfel',
    'İSTANBUL',
    '999',
    'missing',
    '1',
  ];
  return needles[random.nextInt(needles.length)];
}

final _rows = <MockRule>[
  const MockRule(
    id: 'block-user-1',
    pattern: '||ads.example.com^',
    kind: RuleKind.block,
    source: RuleSource.user,
  ),
  const MockRule(
    id: 'block-sub-2',
    pattern: '||tracker.example.net^',
    kind: RuleKind.block,
    source: RuleSource.subscription,
  ),
  const MockRule(
    id: 'block-user-3',
    pattern: '||0.0.0.1 ads.example.org^',
    kind: RuleKind.block,
    source: RuleSource.user,
  ),
  const MockRule(
    id: 'block-preset-4',
    pattern: '||ÄPFEL.example.de^',
    kind: RuleKind.block,
    source: RuleSource.preset,
  ),
];

/// Ids the original Dart filter produced for [_rows]: fold the query, then pattern or target.
List<String> _expectedIds({required RuleSource? source, required String query}) {
  final needle = query.toLowerCase();
  return [
    for (final rule in _rows)
      if ((source == null || rule.source == source) &&
          (needle.isEmpty ||
              rule.pattern.toLowerCase().contains(needle) ||
              (rule.target?.toLowerCase().contains(needle) ?? false)))
        rule.id,
  ];
}

/// Fixed state for one-shot override of the initial-rules provider.
class _FixedInitialRules extends InitialRulesNotifier {
  _FixedInitialRules(this._initial);

  final Map<RuleKind, List<MockRule>> _initial;

  @override
  Map<RuleKind, List<MockRule>> build() => _initial;
}
