/// Dart side of `com.haoze.diting/runtime_log`: the two troubleshooting tiers under
/// 功能中心 → 故障排查 — the on-demand `logcat` capture and the always-on structured runtime-event
/// black box. Kept out of [PlatformBridge] because it has no crash/export coupling.
library;

import 'package:flutter/services.dart';

const runtimeLogChannelName = 'com.haoze.diting/runtime_log';

/// Severity tags shared with the Kotlin `RuntimeEventLog` and the Rust `runtime_event::Level`.
abstract final class RuntimeEventLevel {
  static const debug = 0;
  static const info = 1;
  static const warn = 2;
  static const error = 3;
  static const fatal = 4;
}

/// Whether capture is running, plus what is on disk. Every failure degrades to "off, nothing".
class RuntimeLogStatus {
  const RuntimeLogStatus({
    this.capturing = false,
    this.fileCount = 0,
    this.sizeBytes = 0,
    this.detailed = false,
    this.eventFiles = 0,
    this.eventBytes = 0,
  });

  final bool capturing;
  final int fileCount;
  final int sizeBytes;

  /// Detailed `-b all` capture vs the standard `--uid` one.
  final bool detailed;

  /// The always-on event black box: its two files and their size.
  final int eventFiles;
  final int eventBytes;

  bool get hasLogs => fileCount > 0 || eventFiles > 0;
  bool get hasEvents => eventFiles > 0;

  /// `0 B` / `12.4 KB` / `1.2 MB`; the page shows it next to the switch.
  String get sizeLabel => _label(sizeBytes);

  /// The event black box's size, shown next to the structured timeline.
  String get eventSizeLabel => _label(eventBytes);

  static String _label(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(2)} MB';
  }

  static const unavailable = RuntimeLogStatus();

  static RuntimeLogStatus fromMap(Object? raw) {
    if (raw is! Map) return unavailable;
    return RuntimeLogStatus(
      capturing: raw['capturing'] == true,
      fileCount: (raw['fileCount'] as num?)?.toInt() ?? 0,
      sizeBytes: (raw['sizeBytes'] as num?)?.toInt() ?? 0,
      detailed: raw['detailed'] == true,
      eventFiles: (raw['eventFiles'] as num?)?.toInt() ?? 0,
      eventBytes: (raw['eventBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

class RuntimeLogBridge {
  RuntimeLogBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(runtimeLogChannelName);

  final MethodChannel _channel;

  Future<RuntimeLogStatus> status() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('status');
      return RuntimeLogStatus.fromMap(raw);
    } on MissingPluginException {
      return RuntimeLogStatus.unavailable;
    } on PlatformException {
      return RuntimeLogStatus.unavailable;
    }
  }

  /// True when capture really started; false keeps the switch off instead of lying.
  Future<bool> start({bool detailed = false}) async {
    try {
      return await _channel.invokeMethod<bool>('start', {
            'detailed': detailed,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Switches standard/detailed; the running capture (if any) is re-armed with the new tier.
  Future<RuntimeLogStatus> setMode({required bool detailed}) async {
    try {
      final raw = await _channel.invokeMethod<Object?>('setMode', {
        'detailed': detailed,
      });
      return RuntimeLogStatus.fromMap(raw);
    } on MissingPluginException {
      return RuntimeLogStatus.unavailable;
    } on PlatformException {
      return RuntimeLogStatus.unavailable;
    }
  }

  Future<String> read() async {
    try {
      return await _channel.invokeMethod<String>('read') ?? '';
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
    }
  }

  /// The most recent structured runtime events, oldest first.
  Future<String> readEvents({int limit = 80}) async {
    try {
      return await _channel.invokeMethod<String>('readEvents', {
            'limit': limit,
          }) ??
          '';
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
    }
  }

  /// Fire-and-forget: a startup milestone or a caught error goes into the always-on black box.
  /// Never throws, so callers on the error path can ignore the future.
  Future<void> appendEvent({
    required String module,
    required String event,
    int level = RuntimeEventLevel.info,
    Map<String, Object?> fields = const {},
  }) async {
    try {
      await _channel.invokeMethod<bool>('appendEvent', {
        'module': module,
        'event': event,
        'level': level,
        'fields': fields,
      });
    } on MissingPluginException {
      // The native side is absent (tests / non-Android); dropping an event is fine.
    } on PlatformException {
      // Same: logging must never break the caller.
    }
  }

  Future<int> clear() async {
    try {
      return await _channel.invokeMethod<int>('clear') ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  /// Hands a (filtered) text export to the system share sheet. Never throws.
  Future<bool> shareText({
    required String text,
    String name = 'runtime-events.txt',
  }) async {
    try {
      return await _channel.invokeMethod<bool>('shareText', {
            'text': text,
            'name': name,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
