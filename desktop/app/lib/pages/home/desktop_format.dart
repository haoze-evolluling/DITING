/// Number and duration text for the desktop dashboard. Figures only; every word comes from the ARB.
library;

/// `3d 4h`, `2h 05m`, `7m 12s`. A service that has just started shows seconds, not `0m`.
String desktopUptime(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds <= 0) return '0s';
  final days = duration.inDays;
  final hours = duration.inHours % 24;
  final minutes = duration.inMinutes % 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds % 60}s';
  return '${seconds}s';
}

/// Ratios arrive as 0..1 from the service; a missing value must not read as `0.0%`.
String desktopPercent(double ratio) {
  final percent = (ratio * 100).clamp(0, 100);
  return '${percent.toStringAsFixed(percent < 10 ? 1 : 0)}%';
}

/// Shown where a value is unknown: a dash, never a zero the service did not send.
const desktopNoValue = '\u2014';

String desktopLatency(double milliseconds) => milliseconds <= 0
    ? desktopNoValue
    : '${milliseconds.toStringAsFixed(milliseconds < 10 ? 1 : 0)} ms';

String desktopQps(double qps) => qps.toStringAsFixed(qps < 10 ? 1 : 0);
