/// Server-mode statistics derived from the server's own `dns_log` table.
///
/// The native engine counters reset on every start, so they cannot answer "how much did the
/// server serve over the last seven days". The log table survives restarts; server mode writes it
/// to its own database (`diting_server_logs`), so these figures never include normal/express rows.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/dns_log_repository.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Windows offered by the server log dashboard. The home status card always uses [sevenDays].
enum ServerStatsWindow {
  today,
  sevenDays,
  all;

  String label(AppL10n l10n) => switch (this) {
    ServerStatsWindow.today => l10n.commonToday,
    ServerStatsWindow.sevenDays => l10n.logWindowSevenDays,
    ServerStatsWindow.all => l10n.commonAll,
  };

  /// Local calendar start of the window. "Seven days" means today plus the previous six, so a
  /// user asking for a week sees seven distinct calendar days rather than a sliding 168-hour box.
  DateTime startOf(DateTime now) {
    final dayStart = DateTime(now.year, now.month, now.day);
    return switch (this) {
      ServerStatsWindow.today => dayStart,
      ServerStatsWindow.sevenDays => dayStart.subtract(const Duration(days: 6)),
      ServerStatsWindow.all => DateTime.fromMillisecondsSinceEpoch(0),
    };
  }
}

class ServerStatsWindowNotifier extends Notifier<ServerStatsWindow> {
  @override
  ServerStatsWindow build() => ServerStatsWindow.sevenDays;

  void select(ServerStatsWindow window) {
    if (state == window) return;
    state = window;
  }
}

final serverStatsWindowProvider =
    NotifierProvider<ServerStatsWindowNotifier, ServerStatsWindow>(
      ServerStatsWindowNotifier.new,
    );

/// Real DNS totals over the selected window. Empty when there is no log database yet.
final serverStatsProvider =
    FutureProvider.family<DnsLogDailyStats, ServerStatsWindow>((
      ref,
      window,
    ) async {
      ref.watch(dnsLogRevisionProvider);
      final db = await ref.watch(activeLogDatabaseProvider.future);
      if (db == null) return const DnsLogDailyStats.empty();
      return DnsLogRepository(db)
          .dailyStats(since: window.startOf(DateTime.now()));
    });

/// The fixed window the server status card shows: today plus the previous six days.
final serverSevenDayStatsProvider = FutureProvider<DnsLogDailyStats>(
  (ref) => ref.watch(serverStatsProvider(ServerStatsWindow.sevenDays).future),
);

/// Cache hits as a share of all queries, matching the previous "cache hit rate" reading where a
/// blocked query was still part of the denominator. The aggregate also exposes its own
/// lookup-based rate; this getter keeps the status card's historical meaning.
extension ServerDnsStatsRatio on DnsLogDailyStats {
  double get cacheHitRateOfQueries => total == 0 ? 0 : cached / total;
}
