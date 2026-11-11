/// Dart side of `com.haoze.diting/db_health`: what the native log writers had to drop and why.
///
/// The 2.1.7 failure mode was silent — a locked `diting_database` left every log page empty and
/// nothing said so. These counters make "no logs at all" visible from 故障排查.
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

  /// Rows thrown away because they could not be buffered or persisted at all.
  final int droppedRows;

  /// [droppedRows] split by native `DropReason` key: `overflow`, `tableMissing`, `noDatabase`,
  /// `closed`. Zero entries are kept, so a missing key means an older native side.
  final Map<String, int> droppedByReason;

  /// `table:reason` of the latest drop, e.g. `dns_log:overflow`.
  final String lastDrop;

  /// How many times opening the database failed (a locked file, not a missing one).
  final int openFailures;

  /// Last native failure, e.g. `SQLiteDatabaseLockedException: database is locked`.
  final String lastCause;

  /// Whether the native side could open the database right now, and how it came up.
  final bool probeOk;

  /// No database file yet (first run): not a failure, the Dart side creates the schema.
  final bool probeAbsent;
  final String probeJournalMode;
  final int probeBusyTimeoutMs;
  final String probeCause;

  /// True when nothing was dropped, no open failed, and the connection answers right now.
  /// An empty [probeCause] means the probe never ran (no native channel), not that it failed.
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
