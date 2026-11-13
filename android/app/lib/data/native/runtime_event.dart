/// Parser and aggregate for one structured runtime-event line, e.g.
/// `2026-11-13 22:00:00.123 WARN service engine.stop reason=user`.
///
/// The line is produced by `RuntimeEventLog` (Kotlin) / `runtime_event::format_event` (Rust); this
/// model only reads it back for the troubleshooting timeline and its filters.
library;

import 'package:diting_android/data/native/runtime_log_bridge.dart'
    show RuntimeEventLevel;

class RuntimeEvent {
  const RuntimeEvent({
    required this.raw,
    required this.timeText,
    required this.levelTag,
    required this.levelName,
    required this.module,
    required this.code,
    required this.detail,
  });

  /// The original line, kept so the filtered export is byte-for-byte what was recorded.
  final String raw;
  final String timeText;
  final int levelTag;
  final String levelName;
  final String module;
  final String code;
  final String detail;

  bool get isWarnOrAbove => levelTag >= RuntimeEventLevel.warn;
  bool get isError => levelTag >= RuntimeEventLevel.error;

  /// The `ms=` field, used for the startup-stage budget check.
  int? get elapsedMs {
    final match = RegExp(r'(?:^|\s)ms=(\d+)').firstMatch(detail);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// `null` for a blank or malformed line (a stray logcat line, a half-written record).
  static RuntimeEvent? parse(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    final match = _linePattern.firstMatch(trimmed);
    if (match == null) return null;
    final levelName = match.group(3)!.toUpperCase();
    final levelTag = switch (levelName) {
      'DEBUG' => RuntimeEventLevel.debug,
      'WARN' => RuntimeEventLevel.warn,
      'ERROR' => RuntimeEventLevel.error,
      'FATAL' => RuntimeEventLevel.fatal,
      _ => RuntimeEventLevel.info,
    };
    return RuntimeEvent(
      raw: trimmed,
      timeText: '${match.group(1)} ${match.group(2)}',
      levelTag: levelTag,
      levelName: levelName,
      module: match.group(4)!,
      code: match.group(5)!,
      detail: match.group(6) ?? '',
    );
  }

  /// date, time, LEVEL, module, code, then everything else (the k=v detail) as one group.
  static final _linePattern = RegExp(
    r'^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)(?:\s+([\s\S]*))?$',
  );

  static List<RuntimeEvent> parseAll(String text) => text
      .split('\n')
      .map(parse)
      .whereType<RuntimeEvent>()
      .toList(growable: false);
}

/// What the page header and the anomaly banner need from the current list.
class RuntimeEventSummary {
  const RuntimeEventSummary(this.events);

  final List<RuntimeEvent> events;

  /// A startup stage slower than this is flagged as an anomaly worth investigating.
  static const startupSlowMs = 1500;

  int get count => events.length;
  int get warnOrAbove => events.where((event) => event.isWarnOrAbove).length;
  int get errors => events.where((event) => event.isError).length;

  /// Uncaught crashes recorded by the global handler (module `crash`).
  int get crashes => events.where((event) => event.module == 'crash').length;

  /// Three crashes in the retained window reads as a crash loop, not three unlucky starts.
  bool get hasCrashLoop => crashes >= 3;

  bool get hasSlowStartup =>
      events.any((event) => event.module == 'startup' && (event.elapsedMs ?? 0) > startupSlowMs);

  /// Errors, a slow startup stage, and a crash loop each add one; the number in the banner.
  int get anomalyCount =>
      errors + (hasSlowStartup ? 1 : 0) + (hasCrashLoop ? 1 : 0);

  bool get hasAnomaly => anomalyCount > 0;
}
