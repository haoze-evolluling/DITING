/// Dart side of `com.haoze.diting/troubleshooting_logs`: the per-file log manager behind
/// 故障排查 → 日志管理. Native owns the files; every failure degrades to an empty answer so the
/// page can show "no logs" instead of crashing.
library;

import 'package:flutter/services.dart';

const troubleshootingLogChannelName = 'com.haoze.diting/troubleshooting_logs';

enum TroubleshootLogKind {
  runtime('runtime'),
  crash('crash');

  const TroubleshootLogKind(this.tag);

  final String tag;

  static TroubleshootLogKind? fromTag(Object? raw) {
    for (final kind in values) {
      if (kind.tag == raw) return kind;
    }
    return null;
  }
}

/// One log file in the merged timeline.
class TroubleshootLogEntry {
  const TroubleshootLogEntry({
    required this.kind,
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final TroubleshootLogKind kind;
  final String name;
  final int sizeBytes;
  final DateTime modifiedAt;

  bool get isRuntime => kind == TroubleshootLogKind.runtime;

  String get sizeLabel => formatLogSize(sizeBytes);

  String get timeLabel => formatLogTimestamp(modifiedAt);

  static TroubleshootLogEntry? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final kind = TroubleshootLogKind.fromTag(raw['kind']);
    final name = raw['name'];
    if (kind == null || name is! String || name.isEmpty) return null;
    return TroubleshootLogEntry(
      kind: kind,
      name: name,
      sizeBytes: (raw['sizeBytes'] as num?)?.toInt() ?? 0,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
        (raw['modifiedMs'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// A file's text plus whether the viewer had to cut it short.
class TroubleshootLogRead {
  const TroubleshootLogRead({required this.content, required this.truncated});

  final String? content;
  final bool truncated;

  static const empty = TroubleshootLogRead(content: null, truncated: false);
}

class TroubleshootClearResult {
  const TroubleshootClearResult({this.runtime = 0, this.crash = 0});

  final int runtime;
  final int crash;

  int get total => runtime + crash;

  static const empty = TroubleshootClearResult();
}

String formatLogTimestamp(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

String formatLogSize(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(2)} MB';
}

class TroubleshootingLogBridge {
  TroubleshootingLogBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(troubleshootingLogChannelName);

  final MethodChannel _channel;

  Future<List<TroubleshootLogEntry>> list() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('list');
      final items = raw is Map ? raw['items'] : null;
      if (items is! List) return const [];
      return items
          .map(TroubleshootLogEntry.fromMap)
          .whereType<TroubleshootLogEntry>()
          .toList(growable: false);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  Future<TroubleshootLogRead> read(TroubleshootLogEntry entry) =>
      readByName(kind: entry.kind, name: entry.name);

  /// Reads by identity alone, so the content page can be reached by route without the full entry.
  Future<TroubleshootLogRead> readByName({
    required TroubleshootLogKind kind,
    required String name,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Object?>('read', {
        'kind': kind.tag,
        'name': name,
      });
      if (raw is! Map) return TroubleshootLogRead.empty;
      final content = raw['content'];
      return TroubleshootLogRead(
        content: content is String ? content : null,
        truncated: raw['truncated'] == true,
      );
    } on MissingPluginException {
      return TroubleshootLogRead.empty;
    } on PlatformException {
      return TroubleshootLogRead.empty;
    }
  }

  Future<bool> delete(TroubleshootLogEntry entry) =>
      _entryCall('delete', entry.kind, entry.name);

  Future<bool> share(TroubleshootLogEntry entry) =>
      _entryCall('share', entry.kind, entry.name);

  Future<bool> shareByName({
    required TroubleshootLogKind kind,
    required String name,
  }) => _entryCall('share', kind, name);

  Future<bool> shareAll() async {
    try {
      return await _channel.invokeMethod<bool>('shareAll') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<TroubleshootClearResult> clearAll() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('clearAll');
      if (raw is! Map) return TroubleshootClearResult.empty;
      return TroubleshootClearResult(
        runtime: (raw['runtime'] as num?)?.toInt() ?? 0,
        crash: (raw['crash'] as num?)?.toInt() ?? 0,
      );
    } on MissingPluginException {
      return TroubleshootClearResult.empty;
    } on PlatformException {
      return TroubleshootClearResult.empty;
    }
  }

  Future<bool> _entryCall(
    String method,
    TroubleshootLogKind kind,
    String name,
  ) async {
    try {
      return await _channel.invokeMethod<bool>(method, {
            'kind': kind.tag,
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
