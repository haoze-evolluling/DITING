part of 'mock_data.dart';

/// Service stats shared by server mode and the log overview, filled only from the real engine
/// counters by `ServiceStatsNotifier.applyNative`.
class ServiceStats {
  const ServiceStats({
    required this.queries,
    required this.cacheHits,
    required this.blocked,
    required this.averageLatencyMs,
    required this.uptime,
  });

  final int queries;
  final int cacheHits;
  final int blocked;
  final int averageLatencyMs;
  final Duration uptime;

  double get cacheHitRate => queries == 0 ? 0 : cacheHits / queries;

  /// Always carries seconds: the status card polls every second, and a label that drops the
  /// second field after the first hour would look frozen.
  String get uptimeLabel {
    final hours = uptime.inHours;
    final minutes = uptime.inMinutes % 60;
    final seconds = uptime.inSeconds % 60;
    final l10n = currentL10n;
    if (hours > 0) {
      return '${l10n.durationHours(hours)}${l10n.durationMinutes(minutes)}'
          '${l10n.durationSeconds(seconds)}';
    }
    if (minutes > 0) {
      return '${l10n.durationMinutes(minutes)}${l10n.durationSeconds(seconds)}';
    }
    return l10n.durationSeconds(seconds);
  }
}
