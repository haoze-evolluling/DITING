library;

import 'dart:async';
import 'dart:convert';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum DesktopLiveStatus { passed, blocked, cached, stale, error }

class DesktopLiveQuery {
  const DesktopLiveQuery({
    required this.timestamp,
    required this.domain,
    required this.qtype,
    required this.clientIp,
    required this.clientName,
    required this.durationMs,
    required this.success,
    required this.rcode,
    required this.cacheHit,
    required this.blocked,
    required this.filterRule,
    required this.filterReason,
    required this.errorMessage,
    required this.status,
  });

  factory DesktopLiveQuery.fromJson(
    Map<String, Object?> json, {
    required int timestamp,
  }) {
    final cacheHit = '${json['cacheHit'] ?? ''}';
    final success = json['success'] == true;
    final blocked = json['blocked'] == true;
    final errorMessage = '${json['errorMessage'] ?? ''}';
    final status = errorMessage.isNotEmpty || !success
        ? DesktopLiveStatus.error
        : blocked
        ? DesktopLiveStatus.blocked
        : cacheHit == 'stale'
        ? DesktopLiveStatus.stale
        : cacheHit.isNotEmpty
        ? DesktopLiveStatus.cached
        : DesktopLiveStatus.passed;
    return DesktopLiveQuery(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        timestamp > 0 ? timestamp : DateTime.now().millisecondsSinceEpoch,
      ),
      domain: '${json['domain'] ?? ''}',
      qtype: '${json['qtype'] ?? ''}',
      clientIp: '${json['clientIP'] ?? ''}',
      clientName: '${json['clientName'] ?? ''}',
      durationMs: switch (json['durationMs']) {
        final num value => value.toDouble(),
        final String value => double.tryParse(value) ?? 0,
        _ => 0,
      },
      success: success,
      rcode: '${json['rcode'] ?? ''}',
      cacheHit: cacheHit,
      blocked: blocked,
      filterRule: '${json['filterRule'] ?? ''}',
      filterReason: '${json['filterReason'] ?? ''}',
      errorMessage: errorMessage,
      status: status,
    );
  }

  final DateTime timestamp;
  final String domain;
  final String qtype;
  final String clientIp;
  final String clientName;
  final double durationMs;
  final bool success;
  final String rcode;
  final String cacheHit;
  final bool blocked;
  final String filterRule;
  final String filterReason;
  final String errorMessage;
  final DesktopLiveStatus status;

  String get client => clientName.isNotEmpty ? clientName : clientIp;

  String get blockReason =>
      filterReason.isNotEmpty ? filterReason : filterRule;

  String get responseCode => rcode.isNotEmpty
      ? rcode
      : success
      ? 'NOERROR'
      : 'SERVFAIL';

  String get displayDomain =>
      domain.endsWith('.') ? domain.substring(0, domain.length - 1) : domain;
}

sealed class DesktopEvent {
  const DesktopEvent();
}

class DesktopQueryEvent extends DesktopEvent {
  const DesktopQueryEvent(this.query);

  final DesktopLiveQuery query;
}

class DesktopChannelEvent extends DesktopEvent {
  const DesktopChannelEvent({required this.connected});

  final bool connected;
}

class DesktopEventClient {
  DesktopEventClient({
    required this.config,
    this.reconnectDelay = const Duration(seconds: 3),
    WebSocketChannel Function(Uri uri)? connect,
  }) : _connect = connect ?? WebSocketChannel.connect;

  final DesktopApiConfig config;
  final Duration reconnectDelay;
  final WebSocketChannel Function(Uri) _connect;

  WebSocketChannel? _channel;
  bool _closed = false;

  Uri get uri => Uri(
    scheme: 'ws',
    host: config.host,
    port: config.port,
    path: '/api/v1/events',
    queryParameters: config.token.isEmpty ? null : {'token': config.token},
  );

  Stream<DesktopEvent> get events async* {
    while (!_closed) {
      try {
        final channel = _connect(uri);
        _channel = channel;
        await channel.ready;
        if (_closed) {
          await channel.sink.close();
          return;
        }
        yield const DesktopChannelEvent(connected: true);
        await for (final raw in channel.stream) {
          final query = desktopQueryFromEvent(raw);
          if (query != null) yield DesktopQueryEvent(query);
        }
      } catch (_) {
      }
      if (_closed) return;
      yield const DesktopChannelEvent(connected: false);
      await Future<void>.delayed(reconnectDelay);
    }
  }

  Future<void> close() async {
    _closed = true;
    await _channel?.sink.close();
  }
}

DesktopLiveQuery? desktopQueryFromEvent(Object? raw) {
  if (raw is! String) return null;
  final Map<String, Object?> json;
  try {
    json = (jsonDecode(raw) as Map).cast<String, Object?>();
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
  if (json['type'] != 'query') return null;
  final data = json['data'];
  if (data is! Map) return null;
  return DesktopLiveQuery.fromJson(
    data.cast<String, Object?>(),
    timestamp: switch (json['timestamp']) {
      final num value => value.toInt(),
      final String value => int.tryParse(value) ?? 0,
      _ => 0,
    },
  );
}
