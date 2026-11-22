library;

import 'package:flutter/services.dart';

const dbHealthChannelName = 'com.haoze.diting/db_health';

class DbWriteHealthSnapshot {
  const DbWriteHealthSnapshot({
    this.droppedRows = 0,
    this.droppedByReason = const {},
    this.lastDrop = '',
    this.openFailures = 0,
    this.lastCause = '',
    this.probeOk = false,
    this.probeAbsent = false,
    this.probeJournalMode = '',
    this.probeBusyTimeoutMs = -1,
    this.probeCause = '',
  });

  final int droppedRows;

  final Map<String, int> droppedByReason;

  final String lastDrop;

  final int openFailures;

  final String lastCause;

  final bool probeOk;

  final bool probeAbsent;
  final String probeJournalMode;
  final int probeBusyTimeoutMs;
  final String probeCause;

  bool get healthy =>
      droppedRows == 0 &&
      openFailures == 0 &&
      (probeOk || probeAbsent || probeCause.isEmpty);

  static const unavailable = DbWriteHealthSnapshot();

  static DbWriteHealthSnapshot fromMap(Object? raw) {
    if (raw is! Map) return unavailable;
    return DbWriteHealthSnapshot(
      droppedRows: (raw['droppedRows'] as num?)?.toInt() ?? 0,
      droppedByReason: _counts(raw['droppedByReason']),
      lastDrop: raw['lastDrop'] as String? ?? '',
      openFailures: (raw['openFailures'] as num?)?.toInt() ?? 0,
      lastCause: raw['lastCause'] as String? ?? '',
      probeOk: raw['probeOk'] as bool? ?? false,
      probeAbsent: raw['probeAbsent'] as bool? ?? false,
      probeJournalMode: raw['probeJournalMode'] as String? ?? '',
      probeBusyTimeoutMs: (raw['probeBusyTimeoutMs'] as num?)?.toInt() ?? -1,
      probeCause: raw['probeCause'] as String? ?? '',
    );
  }
}

Map<String, int> _counts(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      if (entry.key is String && entry.value is num)
        entry.key as String: (entry.value as num).toInt(),
  };
}

class DbHealthBridge {
  DbHealthBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(dbHealthChannelName);

  final MethodChannel _channel;

  Future<DbWriteHealthSnapshot> status() async {
    try {
      return DbWriteHealthSnapshot.fromMap(
        await _channel.invokeMethod<Object?>('status'),
      );
    } on MissingPluginException {
      return DbWriteHealthSnapshot.unavailable;
    } on PlatformException {
      return DbWriteHealthSnapshot.unavailable;
    }
  }
}
