/// Dart side of `com.haoze.diting/runtime_log`: the manual logcat capture shown under
/// 功能中心 → 故障排查. Kept out of [PlatformBridge] because it has no crash/export coupling.
library;

import 'package:flutter/services.dart';

const runtimeLogChannelName = 'com.haoze.diting/runtime_log';

/// Whether capture is running, plus what is on disk. Every failure degrades to "off, nothing".
class RuntimeLogStatus {
  const RuntimeLogStatus({
    this.capturing = false,
    this.fileCount = 0,
    this.sizeBytes = 0,
  });

  final bool capturing;
  final int fileCount;
  final int sizeBytes;

  bool get hasLogs => fileCount > 0;

  /// `0 B` / `12.4 KB` / `1.2 MB`; the page shows it next to the switch.
  String get sizeLabel {
    if (sizeBytes <= 0) return '0 B';
    if (sizeBytes < 1024) return '$sizeBytes B';
    final kb = sizeBytes / 1024;
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
  Future<bool> start() async {
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
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

  Future<String> read() async {
    try {
      return await _channel.invokeMethod<String>('read') ?? '';
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
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
}
