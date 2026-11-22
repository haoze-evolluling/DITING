library;

import 'dart:convert';

import 'package:flutter/services.dart';

class FlowRow {
  const FlowRow({
    required this.protocol,
    required this.srcIp,
    required this.srcPort,
    required this.dstIp,
    required this.dstPort,
    required this.uid,
    required this.package,
    required this.domain,
    required this.upBytes,
    required this.downBytes,
    required this.status,
    required this.firstSeenMs,
    required this.lastSeenMs,
    required this.seq,
  });

  final String protocol;
  final String srcIp;
  final int srcPort;
  final String dstIp;
  final int dstPort;
  final int uid;
  final String package;
  final String domain;
  final int upBytes;
  final int downBytes;
  final String status;
  final int firstSeenMs;
  final int lastSeenMs;
  final int seq;

  String get key => '$protocol|$srcIp:$srcPort|$dstIp:$dstPort|$uid';

  String get appLabel {
    if (package.isNotEmpty) return package;
    if (uid >= 0) return 'uid:$uid';
    return 'unknown';
  }

  String get hostLabel => domain.isNotEmpty ? domain : dstIp;

  static FlowRow? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    return FlowRow(
      protocol: (map['protocol'] as String?) ?? '',
      srcIp: (map['srcIp'] as String?) ?? '',
      srcPort: (map['srcPort'] as num?)?.toInt() ?? 0,
      dstIp: (map['dstIp'] as String?) ?? '',
      dstPort: (map['dstPort'] as num?)?.toInt() ?? 0,
      uid: (map['uid'] as num?)?.toInt() ?? 0,
      package: (map['package'] as String?) ?? '',
      domain: (map['domain'] as String?) ?? '',
      upBytes: (map['upBytes'] as num?)?.toInt() ?? 0,
      downBytes: (map['downBytes'] as num?)?.toInt() ?? 0,
      status: (map['status'] as String?) ?? 'active',
      firstSeenMs: (map['firstSeenMs'] as num?)?.toInt() ?? 0,
      lastSeenMs: (map['lastSeenMs'] as num?)?.toInt() ?? 0,
      seq: (map['seq'] as num?)?.toInt() ?? 0,
    );
  }
}

class FlowSnapshot {
  const FlowSnapshot({
    required this.baseSeq,
    required this.nextSeq,
    required this.total,
    required this.truncated,
    required this.rows,
  });

  final int baseSeq;
  final int nextSeq;
  final int total;
  final bool truncated;
  final List<FlowRow> rows;

  static const empty = FlowSnapshot(
    baseSeq: 0,
    nextSeq: 0,
    total: 0,
    truncated: false,
    rows: [],
  );

  static FlowSnapshot fromJson(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) return empty;
    final map = Map<String, Object?>.from(decoded);
    final sessions = (map['sessions'] as List?) ?? const [];
    return FlowSnapshot(
      baseSeq: (map['baseSeq'] as num?)?.toInt() ?? 0,
      nextSeq: (map['nextSeq'] as num?)?.toInt() ?? 0,
      total: (map['total'] as num?)?.toInt() ?? 0,
      truncated: (map['truncated'] as bool?) ?? false,
      rows: [for (final session in sessions) ?FlowRow.fromJson(session)],
    );
  }
}

class FlowBridge {
  const FlowBridge();

  static const _channel = MethodChannel('com.haoze.diting/flow_view');

  Future<FlowSnapshot> snapshot({int sinceSeq = 0, int limit = 500}) async {
    try {
      final text = await _channel.invokeMethod<String>('snapshot', {
        'sinceSeq': sinceSeq,
        'limit': limit,
      });
      return text == null ? FlowSnapshot.empty : FlowSnapshot.fromJson(text);
    } on PlatformException {
      return FlowSnapshot.empty;
    } on MissingPluginException {
      return FlowSnapshot.empty;
    }
  }
}
