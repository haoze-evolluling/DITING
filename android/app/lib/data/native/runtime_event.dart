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

  final String raw;
  final String timeText;
  final int levelTag;
  final String levelName;
  final String module;
  final String code;
  final String detail;

  bool get isWarnOrAbove => levelTag >= RuntimeEventLevel.warn;
  bool get isError => levelTag >= RuntimeEventLevel.error;

  int? get elapsedMs {
    final match = RegExp(r'(?:^|\s)ms=(\d+)').firstMatch(detail);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

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

  static final _linePattern = RegExp(
    r'^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)(?:\s+([\s\S]*))?$',
  );

  static List<RuntimeEvent> parseAll(String text) => text
      .split('\n')
      .map(parse)
      .whereType<RuntimeEvent>()
      .toList(growable: false);
}

class RuntimeEventSummary {
  const RuntimeEventSummary(this.events);

  final List<RuntimeEvent> events;

  static const startupSlowMs = 1500;

  int get count => events.length;
  int get warnOrAbove => events.where((event) => event.isWarnOrAbove).length;
  int get errors => events.where((event) => event.isError).length;

  int get crashes => events.where((event) => event.module == 'crash').length;

  bool get hasCrashLoop => crashes >= 3;

  bool get hasSlowStartup =>
      events.any((event) => event.module == 'startup' && (event.elapsedMs ?? 0) > startupSlowMs);

  int get anomalyCount =>
      errors + (hasSlowStartup ? 1 : 0) + (hasCrashLoop ? 1 : 0);

  bool get hasAnomaly => anomalyCount > 0;
}
