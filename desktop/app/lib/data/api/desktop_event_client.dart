/// The service's push channel: `/api/v1/events` sends one JSON event per DNS query, which is what
/// makes a live list possible without polling the query log.
///
/// The channel is the same one the old desktop console subscribes to
/// (`frontend/src/api/ws.ts`): the token travels as a query parameter, because a browser WebSocket
/// handshake cannot carry the `Authorization` header, and a dropped socket is retried after a
/// short delay. Nothing here decides how a query looks; it only turns the pushed payload into
/// [DesktopLiveQuery].
library;

import 'dart:async';
import 'dart:convert';

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// How the service classified one pushed query. The service sends flags rather than a word, so the
/// order of these checks is the classification (`errorMessage`/`success`, then blocked, then cache).
enum DesktopLiveStatus { passed, blocked, cached, stale, error }

/// One `QueryEventData` from `/api/v1/events`, with the connection's timestamp.
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

  /// The name the console shows: the friendly host name when the service resolved one, else the
  /// address it came from.
  String get client => clientName.isNotEmpty ? clientName : clientIp;

  /// Why the rule engine blocked it, when the service said why.
  String get blockReason =>
      filterReason.isNotEmpty ? filterReason : filterRule;

  /// `NOERROR` / `NXDOMAIN` / `SERVFAIL`, derived only when the service omitted the code: the
  /// console filters on these three words.
  String get responseCode => rcode.isNotEmpty
      ? rcode
      : success
      ? 'NOERROR'
      : 'SERVFAIL';

  /// The service stores the trailing dot of the queried name; it reads as noise in a list.
  String get displayDomain =>
      domain.endsWith('.') ? domain.substring(0, domain.length - 1) : domain;
}

/// One item on the push channel: a query, or a change in whether the channel is up. Both arrive on
/// the same stream so the list can say "disconnected" without a second source of truth.
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

/// Reads `/api/v1/events`, retrying while the service is away.
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

  /// The token goes in the query string: a WebSocket handshake from a page cannot set headers, and
  /// the service accepts the same token there (`ipc.extractToken`).
  Uri get uri => Uri(
    scheme: 'ws',
    host: config.host,
    port: config.port,
    path: '/api/v1/events',
    queryParameters: config.token.isEmpty ? null : {'token': config.token},
  );

  /// Queries as they happen, plus connection changes, until [close]. Single-subscription: the live
  /// list is the only reader, and a second one would double the traffic.
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
        // A closed socket, a refused connection or a payload this build cannot read: the retry
        // below is the answer to all three, and the list reports the gap honestly.
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

/// Only `type: "query"` events are queries; every other event type (dns, takeover, filter) belongs
/// to another branch, and a payload this build cannot read is dropped rather than guessed at.
///
/// Top-level and public so the wire format can be pinned by a test without opening a socket.
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
