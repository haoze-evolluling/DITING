#!/usr/bin/env dart
/// Compares the Dart rule filter with the native rule search index on a subscription-sized table.
///
/// ```bash
/// cd android/app
/// dart run tool/rule_search_bench.dart                 # JIT, quick sanity check
/// dart compile exe tool/rule_search_bench.dart -o build/rule_search_bench.exe
/// build/rule_search_bench.exe                          # AOT: the numbers a release APK sees
/// ```
///
/// The Rust library is found the same way the app finds it (`DITING_RULE_CORE_LIB`, the packaged
/// name, or `rust/target/<profile>/`); build it first with `cargo build --release` in `rust/`.
/// Without it the run reports the Dart baseline only.
library;

import 'dart:io';

import 'package:diting_android/data/rules/rule_search_index.dart';
import 'package:diting_android/data/rules/rust_rule_core.dart';

const _rowCount = 100000;
const _queries = <String>[
  'ads',
  'tracker',
  'example',
  '.com^',
  'analytics',
  'nothing-matches-this',
];
const _runs = 3;

void main(List<String> arguments) {
  final rows = arguments.isEmpty ? _rowCount : int.parse(arguments.first);
  final entries = _synthetic(rows);
  stdout.writeln('rows: $rows, bytes: ${_bytes(entries)}');

  final dart = _measure(() {
    var hits = 0;
    for (final query in _queries) {
      hits += _dartMatches(entries, query);
    }
    return hits;
  });
  _report('dart', _queries.length, dart, '');

  final core = RustRuleCore.instance;
  if (core == null || !core.supportsSearch) {
    stdout.writeln('rust: search unavailable — build with `cargo build --release` in rust/');
    return;
  }

  final index = RuleSearchIndex(() => entries);
  try {
    // The first query is what folds the table; time it separately instead of folding it in the
    // average. Nothing outside this stopwatch may touch the index.
    final build = Stopwatch()..start();
    final probe = index.match('ads');
    build.stop();
    if (probe == null) {
      stdout.writeln('rust: index rejected — using the Dart filter');
      return;
    }
    final rust = _measure(() {
      var hits = 0;
      for (final query in _queries) {
        hits += index.match(query)!.length;
      }
      return hits;
    });
    _report('rust', _queries.length, rust, ', build ${build.elapsedMilliseconds} ms');

    // The two paths must agree on what they return, not just on how fast they do it.
    for (final query in _queries) {
      final expected = _dartMatches(entries, query);
      final actual = index.match(query)!.length;
      if (expected != actual) {
        stdout.writeln('MISMATCH "$query": dart $expected, rust $actual');
      }
    }
    stdout.writeln(
      'speedup: ${(dart / rust).toStringAsFixed(1)}x (dart/rust, per query)',
    );
  } finally {
    index.dispose();
  }
}

int _bytes(List<RuleSearchEntry> entries) {
  var total = 0;
  for (final entry in entries) {
    total += entry.pattern.length + (entry.target?.length ?? 0);
  }
  return total;
}

/// Best of `_runs`, to keep JIT/GC warm-up out of the comparison.
int _measure(int Function() body) {
  var best = 1 << 62;
  for (var run = 0; run < _runs + 1; run++) {
    final stopwatch = Stopwatch()..start();
    body();
    stopwatch.stop();
    if (run > 0 && stopwatch.elapsedMicroseconds < best) {
      best = stopwatch.elapsedMicroseconds;
    }
  }
  return best;
}

void _report(String label, int queries, int microseconds, String suffix) {
  final millis = microseconds / 1000 / queries;
  stdout.writeln('$label: ${millis.toStringAsFixed(2)} ms/query (${queries - 1} queries)$suffix');
}

/// The filter the rules page ran before the migration.
int _dartMatches(List<RuleSearchEntry> entries, String query) {
  final needle = query.toLowerCase();
  var hits = 0;
  for (final entry in entries) {
    if (entry.pattern.toLowerCase().contains(needle) ||
        (entry.target?.toLowerCase().contains(needle) ?? false)) {
      hits++;
    }
  }
  return hits;
}

/// A table shaped like a real subscription import: domain rules, adblock syntax, hosts lines and
/// some rewrite targets.
List<RuleSearchEntry> _synthetic(int count) => [
  for (var index = 0; index < count; index++)
    switch (index % 5) {
      0 => (pattern: '||ads$index.example.com^', target: null),
      1 => (pattern: '||tracker$index.analytics.net^', target: null),
      2 => (pattern: '0.0.0.0 metric$index.example.org', target: null),
      3 => (pattern: 'example$index.com##.ad-banner', target: null),
      _ => (
        pattern: '||safe$index.example.com^',
        target: '10.0.${index % 256}.1',
      ),
    },
];
