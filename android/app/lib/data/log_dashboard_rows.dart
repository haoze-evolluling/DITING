library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/dns_log_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_android/data/db/rust_log_query_core.dart';
import 'package:diting_android/data/dns_type_name.dart';
import 'package:diting_android/data/log_dashboard_models.dart';

String dashboardClockOf(int milliseconds) {
  if (milliseconds <= 0) return '--:--:--';
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

bool isConnectionLog({
  required int queryType,
  required String queryName,
  String? message,
}) =>
    RustLogQueryCore.instance.classify('dnsConnection', {
          'queryType': queryType,
          'queryName': queryName,
          'message': message,
        })['value']
        as bool? ??
    false;

String dnsResultLabelOf(String result, {required bool isConnection}) =>
    switch (result) {
      'PASSED' =>
        isConnection ? currentL10n.commonBypass : currentL10n.logPassed,
      'REWRITTEN' => currentL10n.commonRewrite,
      'BLOCKED' => currentL10n.logFiltered,
      'ERROR' => currentL10n.commonFailed,
      _ => result,
    };

LogRowStatus dnsRowStatusOf(
  String result, {
  required bool isConnection,
  required bool cached,
}) {
  final token =
      RustLogQueryCore.instance.classify('dnsLogStatus', {
            'result': result,
            'isConnection': isConnection,
            'cached': cached,
          })['status']
          as String?;
  return _logRowStatus(token);
}

LogRowStatus _logRowStatus(String? token) => switch (token) {
  'passed' => LogRowStatus.passed,
  'filtered' => LogRowStatus.filtered,
  'failed' => LogRowStatus.failed,
  'bypassed' => LogRowStatus.bypassed,
  'cached' => LogRowStatus.cached,
  _ => LogRowStatus.failed,
};

String dnsRowMetaOf({
  required int queryType,
  required String queryName,
  required bool cached,
  String? message,
  String? packageName,
}) {
  final connection = isConnectionLog(
    queryType: queryType,
    queryName: queryName,
    message: message,
  );
  if (connection) {
    final protocol = queryName.startsWith('UDP') ? 'UDP' : 'TCP';
    return packageName == null || packageName.isEmpty
        ? currentL10n.logDirect(protocol)
        : currentL10n.logDirectWithApp(protocol, packageName);
  }
  final parts = <String>[dnsTypeName(queryType)];
  if (cached) parts.add(currentL10n.logRowCacheHit);
  if (message != null && message.isNotEmpty) parts.add(message);
  return parts.join(' · ');
}

String dnsRowSourceOf({required int queryType, required String queryName}) {
  final connection = isConnectionLog(
    queryType: queryType,
    queryName: queryName,
  );
  if (!connection) return 'DNS';
  return queryName.startsWith('UDP') ? 'UDP' : 'TCP';
}

LogRecentRequest logRecentRequestOfDns(DnsLogRecord row) {
  final connection = isConnectionLog(
    queryType: row.queryType,
    queryName: row.domain,
    message: row.message,
  );
  return LogRecentRequest(
    time: dashboardClockOf(row.timestamp),
    name: row.domain,
    source: dnsRowSourceOf(queryType: row.queryType, queryName: row.domain),
    meta: dnsRowMetaOf(
      queryType: row.queryType,
      queryName: row.domain,
      cached: row.cached,
      message: row.message,
      packageName: row.packageName,
    ),
    resultLabel: dnsResultLabelOf(row.result, isConnection: connection),
    status: dnsRowStatusOf(
      row.result,
      isConnection: connection,
      cached: row.cached,
    ),
  );
}

LogRecentRequest logRecentRequestOfHttp(HttpRequestRecord row) {
  final status = httpRowStatusOf(row.outcome);
  final authority = row.authority ?? '';
  final matchedRule = row.matchedRule ?? '';
  final meta = <String>[
    if (row.protocol.isNotEmpty) row.protocol,
    if (row.packageName.isNotEmpty) row.packageName,
    if (matchedRule.isNotEmpty) matchedRule,
  ].join(' · ');
  return LogRecentRequest(
    time: dashboardClockOf(row.timestamp),
    name: authority.isEmpty ? currentL10n.logRowNoAuthority : authority,
    source: 'HTTPS',
    meta: meta,
    resultLabel: switch (status) {
      LogRowStatus.filtered => currentL10n.logFiltered,
      LogRowStatus.bypassed => currentL10n.commonBypass,
      LogRowStatus.failed => currentL10n.commonFailed,
      _ => currentL10n.logPassed,
    },
    status: status,
  );
}

LogRowStatus httpRowStatusOf(String outcome) => _logRowStatus(
  RustLogQueryCore.instance.classify('httpLogStatus', {
        'outcome': outcome,
      })['status']
      as String?,
);

bool httpOutcomeIsPassed(String outcome) =>
    RustLogQueryCore.instance.classify('httpPassed', {
          'outcome': outcome,
        })['value']
        as bool? ??
    false;
