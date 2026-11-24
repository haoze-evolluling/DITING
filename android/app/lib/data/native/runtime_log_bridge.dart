library;

import 'package:diting_shared/data/errors.dart';
import 'package:flutter/services.dart';

const runtimeLogChannelName = 'com.haoze.diting/runtime_log';

abstract final class RuntimeEventLevel {
  static const debug = 0;
  static const info = 1;
  static const warn = 2;
  static const error = 3;
  static const fatal = 4;
}

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

  final bool detailed;

  final int eventFiles;
  final int eventBytes;

  bool get hasLogs => fileCount > 0 || eventFiles > 0;

  String get sizeLabel => _label(sizeBytes);

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
      ignoreError();
    } on PlatformException {
      ignoreError();
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
