library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/db/http_request_repository.dart'
    show RequestSource, RequestStatus;

enum RequestLogExportRange { all, hour, day, week, custom }

const int requestLogExportDefaultRows = 1000;
const int requestLogExportMaxRows = 50000;

enum RequestLogColumn {
  time,
  source,
  status,
  appName,
  packageName,
  host,
  protocol,
  rule,
  elapsed,
  cached,
  subscription,
  message;

  String header(AppL10n l10n) => switch (this) {
    RequestLogColumn.time => l10n.obsExportColumnTime,
    RequestLogColumn.source => l10n.obsExportColumnSource,
    RequestLogColumn.status => l10n.obsExportColumnStatus,
    RequestLogColumn.appName => l10n.obsExportColumnAppName,
    RequestLogColumn.packageName => l10n.obsExportColumnPackage,
    RequestLogColumn.host => l10n.obsExportColumnHost,
    RequestLogColumn.protocol => l10n.obsExportColumnProtocol,
    RequestLogColumn.rule => l10n.obsExportColumnRule,
    RequestLogColumn.elapsed => l10n.obsExportColumnElapsed,
    RequestLogColumn.cached => l10n.obsExportColumnCached,
    RequestLogColumn.subscription => l10n.obsExportColumnSubscription,
    RequestLogColumn.message => l10n.obsExportColumnMessage,
  };
}

class RequestLogExportOptions {
  const RequestLogExportOptions({
    this.source = RequestSource.all,
    this.status = RequestStatus.all,
    this.packages = const {},
    this.range = RequestLogExportRange.all,
    this.customStart,
    this.customEnd,
    this.maxRows = requestLogExportDefaultRows,
    this.columns = const {...RequestLogColumn.values},
  });

  final RequestSource source;
  final RequestStatus status;

  final Set<String> packages;
  final RequestLogExportRange range;
  final DateTime? customStart;
  final DateTime? customEnd;
  final int maxRows;
  final Set<RequestLogColumn> columns;

  int? sinceMs(DateTime now) => switch (range) {
    RequestLogExportRange.all => null,
    RequestLogExportRange.hour =>
      now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
    RequestLogExportRange.day =>
      now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
    RequestLogExportRange.week =>
      now.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
    RequestLogExportRange.custom => customStart?.millisecondsSinceEpoch,
  };

  int? untilMs(DateTime now) => switch (range) {
    RequestLogExportRange.all => null,
    RequestLogExportRange.hour ||
    RequestLogExportRange.day ||
    RequestLogExportRange.week => now.millisecondsSinceEpoch,
    RequestLogExportRange.custom => customEnd?.millisecondsSinceEpoch,
  };
}
