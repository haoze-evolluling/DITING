/// Data for the log dashboard "statistics" card: request and data-usage totals over a chosen
/// [TrafficWindow], each section with its own window.
library;

import 'package:diting_android/data/db/dns_cache_repository.dart';
import 'package:diting_android/data/db/dns_log_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_android/data/db/rust_log_query_core.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/observability_providers.dart';
import 'package:diting_android/state/traffic_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

/// The card's two sections; each remembers its window for the app session.
enum LogStatsSection { requests, data }

final logStatsWindowProvider =
    NotifierProvider.family<
      LogStatsWindowNotifier,
      TrafficWindow,
      LogStatsSection
    >(LogStatsWindowNotifier.new);

class LogStatsWindowNotifier extends Notifier<TrafficWindow> {
  LogStatsWindowNotifier(this.section);

  final LogStatsSection section;

  @override
  TrafficWindow build() => TrafficWindow.today;

  void select(TrafficWindow window) => state = window;
}

/// Local start of [window]: midnight today, Monday, the 1st, or the epoch for all history.
/// Matches the calendar windows of the traffic page.
DateTime logStatsWindowStart(TrafficWindow window, [DateTime? now]) {
  final today = now ?? DateTime.now();
  final midnight = DateTime(today.year, today.month, today.day);
  return switch (window) {
    TrafficWindow.today => midnight,
    TrafficWindow.week => midnight.subtract(Duration(days: today.weekday - 1)),
    TrafficWindow.month => DateTime(today.year, today.month),
    TrafficWindow.all => DateTime.fromMillisecondsSinceEpoch(0),
  };
}

/// [cached] never overlaps [blocked]: a cached answer is a passed one.
typedef LogStatsRequests = ({int total, int blocked, int cached});

/// [saved] is an estimate: cached answers in the window times the average cached response size,
/// the bytes an upstream query would have returned.
typedef LogStatsData = ({int saved, int uploaded, int downloaded});

/// Same sources and counting as the request overview card, over [TrafficWindow] instead of today.
final logStatsRequestsProvider =
    FutureProvider.family<LogStatsRequests, TrafficWindow>((ref, window) async {
      ref.watch(dnsLogRevisionProvider);
      final express = ref.watch(workModeProvider) == AppWorkMode.express;
      final since = logStatsWindowStart(window);
      final db = await ref.watch(activeLogDatabaseProvider.future);
      if (db == null) return (total: 0, blocked: 0, cached: 0);

      final dns = await DnsLogRepository(db).dailyStats(since: since);
      var http = const HttpRequestDailyStats.empty();
      if (!express) {
        final mainDb = await ref.watch(mainLogDatabaseProvider.future);
        if (mainDb != null) {
          try {
            http = await HttpRequestRepository(mainDb).dailyStats(since: since);
          } on DatabaseException {
            // Older schema without the HTTPS table: DNS rows only.
          }
        }
      }
      final answer = RustLogQueryCore.instance.derive('stats.requests', {
        'dns': dns.toKernel(),
        'http': http.toKernel(),
      });
      return (
        total: (answer['total'] as num?)?.toInt() ?? 0,
        blocked: (answer['blocked'] as num?)?.toInt() ?? 0,
        cached: (answer['cached'] as num?)?.toInt() ?? 0,
      );
    });

final logStatsDataProvider = FutureProvider.family<LogStatsData, TrafficWindow>(
  (ref, window) async {
    final traffic = await ref.watch(trafficSnapshotOfProvider(window).future);
    final db = await ref.watch(activeLogDatabaseProvider.future);
    var cached = 0;
    var average = 0.0;
    if (db != null) {
      final since = logStatsWindowStart(window);
      cached = (await DnsLogRepository(db).dailyStats(since: since)).cached;
      average = await DnsCacheRepository(db).averageResponseSize();
    }
    final answer = RustLogQueryCore.instance.derive('stats.data', {
      'cached': cached,
      'avgResponseSize': average,
      'txBytes': traffic.txBytes,
      'rxBytes': traffic.rxBytes,
    });
    return (
      saved: (answer['saved'] as num?)?.toInt() ?? 0,
      uploaded: (answer['uploaded'] as num?)?.toInt() ?? 0,
      downloaded: (answer['downloaded'] as num?)?.toInt() ?? 0,
    );
  },
);
