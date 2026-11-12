/// Turns the request log into CSV. Rows come from both tables with the same filters the list page
/// uses; the CSV is written in chunks so a large export never exists as one string.
library;

import 'package:diting_android/data/db/dns_query_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_android/data/export/request_log_export_options.dart';
import 'package:diting_android/state/observability_providers.dart'
    show ObservedRequest;
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:sqflite/sqflite.dart';

/// The databases an export reads from. A null side is skipped: express and server modes have no
/// `http_request_log`, and a fresh install may have no file yet.
class RequestLogExportSource {
  const RequestLogExportSource({this.dnsDb, this.httpDb});

  final Database? dnsDb;
  final Database? httpDb;
}

class RequestLogExportResult {
  const RequestLogExportResult({required this.count, required this.truncated});

  final int count;

  /// True when more rows matched than [RequestLogExportOptions.maxRows].
  final bool truncated;
}

/// Receives the CSV as it is produced.
typedef RequestLogCsvSink = Future<void> Function(String chunk);

class RequestLogCsvExporter {
  const RequestLogCsvExporter();

  /// Chunk size handed to the sink; keeps the Dart side from holding the whole document.
  static const _flushChars = 64 * 1024;

  Future<RequestLogExportResult> exportTo(
    RequestLogCsvSink sink, {
    required RequestLogExportOptions options,
    required RequestLogExportSource source,
    required Map<String, String> appLabels,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final since = options.sinceMs(at);
    final until = options.untilMs(at);
    final limit = options.maxRows.clamp(1, requestLogExportMaxRows);
    final status = options.status;

    // One extra row per table is not needed: each table is capped at `limit`, so the merged top
    // `limit` cannot miss a row that belongs in it.
    final dnsFuture =
        options.source == RequestSource.https || source.dnsDb == null
        ? Future.value(const <DnsLogRow>[])
        : DnsQueryRepository(source.dnsDb!).export(
            limit: limit,
            status: status,
            since: since,
            until: until,
            packages: options.packages,
          );
    final httpFuture =
        options.source == RequestSource.dns || source.httpDb == null
        ? Future.value(const <HttpRequestRecord>[])
        : HttpRequestRepository(source.httpDb!).export(
            limit: limit,
            status: status,
            since: since,
            until: until,
            packages: options.packages,
          );

    // Await together: a sequential await would leave the other error unhandled when one throws.
    final (dnsRows, httpRows) = await (dnsFuture, httpFuture).wait;

    final merged =
        <ObservedRequest>[
          for (final row in dnsRows) ObservedRequest.fromDns(row),
          for (final row in httpRows) ObservedRequest.fromHttp(row),
        ]..sort((a, b) {
          final byTime = b.timestamp.compareTo(a.timestamp);
          // A stable tie-break keeps two exports of the same window identical.
          return byTime != 0 ? byTime : b.key.compareTo(a.key);
        });
    final truncated = merged.length > limit;
    final rows = truncated ? merged.sublist(0, limit) : merged;

    final columns = [
      for (final column in RequestLogColumn.values)
        if (options.columns.contains(column)) column,
    ];

    final buffer = StringBuffer();
    var pending = 0;

    Future<void> emit(String text) async {
      buffer.write(text);
      pending += text.length;
      if (pending >= _flushChars) {
        await sink(buffer.toString());
        buffer.clear();
        pending = 0;
      }
    }

    // Excel needs the BOM to read UTF-8; CRLF matches what spreadsheet apps expect.
    buffer.write('\uFEFF');
    pending = 3;
    await emit(
      _line([for (final column in columns) column.header(currentL10n)]),
    );
    for (final request in rows) {
      await emit(
        _line([
          for (final column in columns) _valueOf(column, request, appLabels),
        ]),
      );
    }
    if (buffer.isNotEmpty) await sink(buffer.toString());

    return RequestLogExportResult(count: rows.length, truncated: truncated);
  }

  static String _line(List<String> fields) =>
      '${fields.map(_escapeField).join(',')}\r\n';

  /// RFC 4180: every field quoted, embedded quotes doubled. Quoting everything keeps commas,
  /// newlines and leading/trailing spaces intact in any spreadsheet app.
  static String _escapeField(String value) =>
      '"${value.replaceAll('"', '""')}"';

  static String _valueOf(
    RequestLogColumn column,
    ObservedRequest request,
    Map<String, String> appLabels,
  ) {
    final packageName = request.packageName ?? '';
    return switch (column) {
      RequestLogColumn.time => _stampOf(request.timestamp),
      RequestLogColumn.source => request.source.label,
      RequestLogColumn.status => request.status.label,
      RequestLogColumn.appName =>
        packageName.isEmpty ? '' : (appLabels[packageName] ?? packageName),
      RequestLogColumn.packageName => packageName,
      RequestLogColumn.host => request.title,
      RequestLogColumn.protocol => request.protocol ?? '',
      RequestLogColumn.rule => request.matchedRule ?? '',
      RequestLogColumn.elapsed => request.elapsedMs?.toString() ?? '',
      RequestLogColumn.cached =>
        request.source == RequestSource.dns
            ? (request.cached
                  ? currentL10n.obsExportCachedYes
                  : currentL10n.obsExportCachedNo)
            : '',
      RequestLogColumn.subscription =>
        request.blockSubscriptionId == null
            ? ''
            : 'sub_${request.blockSubscriptionId}',
      RequestLogColumn.message => request.message ?? '',
    };
  }

  static String _stampOf(int timestamp) {
    final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
