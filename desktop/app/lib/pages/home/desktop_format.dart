library;

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

String desktopPercent(double ratio) {
  final percent = (ratio * 100).clamp(0, 100);
  return '${percent.toStringAsFixed(percent < 10 ? 1 : 0)}%';
}

const desktopNoValue = '\u2014';

String desktopLatency(double milliseconds) => milliseconds <= 0
    ? desktopNoValue
    : '${milliseconds.toStringAsFixed(milliseconds < 10 ? 1 : 0)} ms';

String desktopQps(double qps) => qps.toStringAsFixed(qps < 10 ? 1 : 0);
