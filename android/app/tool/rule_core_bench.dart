#!/usr/bin/env dart
/// Compares the Dart rule parser with the Rust core on a subscription-sized list.
///
/// ```bash
/// cd android/app
/// dart run tool/rule_core_bench.dart                 # JIT, quick sanity check
/// dart compile exe tool/rule_core_bench.dart -o build/rule_core_bench.exe
/// build/rule_core_bench.exe                          # AOT: the numbers a release APK sees
/// ```
///
/// The Rust library is found the same way the app finds it (`DITING_RULE_CORE_LIB`, the packaged
/// name, or `rust/target/<profile>/`); build it first with `cargo build --release` in `rust/`.
/// Without it the run reports the Dart baseline only.
library;

import 'dart:io';

import 'package:diting_android/data/rules/rule_parser.dart';
import 'package:diting_android/data/rules/rust_rule_core.dart';

const _lineCount = 100000;
const _runs = 3;

void main(List<String> arguments) {
  final lines = arguments.isEmpty ? _lineCount : int.parse(arguments.first);
  final text = _syntheticList(lines);
  final core = RustRuleCore.instance;

  stdout.writeln('lines: $lines, bytes: ${text.length}');
  stdout.writeln('dart: ${parseCategorizedInDart(text).totalLines} lines parsed');
  if (core == null) {
    stdout.writeln('rust: library not loaded — build it with `cargo build --release` in rust/');
  } else {
    stdout.writeln('rust: ${core.tryParse(text)!.totalLines} lines parsed from ${core.libraryPath}');
  }
  stdout.writeln('');

  final dart = _measure(() => parseCategorizedInDart(text).size);
  final rust = core == null ? null : _measure(() => core.tryParse(text)!.size);
  _report('dart', lines, dart);
  if (rust != null) {
    _report('rust', lines, rust);
    final speedup = dart / rust;
    stdout.writeln('speedup: ${speedup.toStringAsFixed(1)}x (dart/rust, includes payload decode)');
  }
}

/// Best of `_runs`, to keep the JIT/GC warm-up out of the comparison.
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

void _report(String label, int lines, int microseconds) {
  final millis = microseconds / 1000;
  final perSecond = lines / (microseconds / 1000000);
  stdout.writeln(
    '$label: ${millis.toStringAsFixed(1)} ms '
    '(${(perSecond / 1000).toStringAsFixed(0)}k lines/s)',
  );
}

/// A list shaped like a real subscription: domain rules, hosts, cosmetic, regex and a few
/// duplicates, so the aggregation path (not just the per-line parser) is measured.
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
