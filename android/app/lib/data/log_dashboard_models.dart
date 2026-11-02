library;

import 'package:diting_shared/app/l10n/l10n.dart';

enum LogRowStatus { passed, filtered, failed, bypassed, cached }

/// DNS resolution quality from today's `dns_log` rows. [cacheHitRate] divides by `passed + error`
/// only.
class LogDnsQuality {
  const LogDnsQuality({
    required this.averageLatencyMs,
    required this.latencySamples,
    required this.cacheHitRate,
  });

  const LogDnsQuality.empty()
    : averageLatencyMs = null,
      latencySamples = 0,
      cacheHitRate = 0;

  final double? averageLatencyMs;
  final int latencySamples;
  final double cacheHitRate;

  // Value equality lets an unchanged refresh skip rebuilding the cards.
  @override
  bool operator ==(Object other) =>
      other is LogDnsQuality &&
      other.averageLatencyMs == averageLatencyMs &&
      other.latencySamples == latencySamples &&
      other.cacheHitRate == cacheHitRate;

  @override
  int get hashCode =>
      Object.hash(averageLatencyMs, latencySamples, cacheHitRate);
}

class LogTrafficBreakdown {
  const LogTrafficBreakdown({
    required this.total,
    required this.passed,
    required this.blocked,
    required this.error,
    required this.bypassed,
    required this.cached,
  });

  const LogTrafficBreakdown.empty()
    : total = 0,
      passed = 0,
      blocked = 0,
      error = 0,
      bypassed = 0,
      cached = 0;

  final int total;
  final int passed;
  final int blocked;
  final int error;
  final int bypassed;

  /// Cache hits, a subset of [passed]; the legacy UI gave it its own legend.
  final int cached;

  double get blockRate => total == 0 ? 0 : blocked / total;

  double get cacheRate => total == 0 ? 0 : cached / total;

  // Value equality lets an unchanged refresh skip rebuilding the cards.
  @override
  bool operator ==(Object other) =>
      other is LogTrafficBreakdown &&
      other.total == total &&
      other.passed == passed &&
      other.blocked == blocked &&
      other.error == error &&
      other.bypassed == bypassed &&
      other.cached == cached;

  @override
  int get hashCode =>
      Object.hash(total, passed, blocked, error, bypassed, cached);
}

class LogRaceSummary {
  const LogRaceSummary({
    required this.requests,
    required this.successes,
    required this.averageElapsedMs,
  });

  const LogRaceSummary.empty()
    : requests = 0,
      successes = 0,
      averageElapsedMs = 0;

  final int requests;
  final int successes;
  final double averageElapsedMs;

  double get successRate => requests == 0 ? 0 : successes / requests;

  // Value equality lets an unchanged refresh skip rebuilding the cards.
  @override
  bool operator ==(Object other) =>
      other is LogRaceSummary &&
      other.requests == requests &&
      other.successes == successes &&
      other.averageElapsedMs == averageElapsedMs;

  @override
  int get hashCode => Object.hash(requests, successes, averageElapsedMs);
}

class LogBootstrapSummary {
  const LogBootstrapSummary({
    required this.attempts,
    required this.successes,
    required this.averageElapsedMs,
  });

  const LogBootstrapSummary.empty()
    : attempts = 0,
      successes = 0,
      averageElapsedMs = 0;

  final int attempts;
  final int successes;
  final double averageElapsedMs;

  double get successRate => attempts == 0 ? 0 : successes / attempts;

  // Value equality lets an unchanged refresh skip rebuilding the cards.
  @override
  bool operator ==(Object other) =>
      other is LogBootstrapSummary &&
      other.attempts == attempts &&
      other.successes == successes &&
      other.averageElapsedMs == averageElapsedMs;

  @override
  int get hashCode => Object.hash(attempts, successes, averageElapsedMs);
}

class LogOffModeStats {
  const LogOffModeStats({
    required this.cacheEntries,
    required this.cacheHits,
    required this.raceRequests,
    required this.bootstrapAttempts,
  });

  const LogOffModeStats.empty()
    : cacheEntries = 0,
      cacheHits = 0,
      raceRequests = 0,
      bootstrapAttempts = 0;

  final int cacheEntries;
  final int cacheHits;
  final int raceRequests;
  final int bootstrapAttempts;

  // Value equality lets an unchanged refresh skip rebuilding the cards.
  @override
  bool operator ==(Object other) =>
      other is LogOffModeStats &&
      other.cacheEntries == cacheEntries &&
      other.cacheHits == cacheHits &&
      other.raceRequests == raceRequests &&
      other.bootstrapAttempts == bootstrapAttempts;

  @override
  int get hashCode =>
      Object.hash(cacheEntries, cacheHits, raceRequests, bootstrapAttempts);
}

/// One recent request. [time] is derived from the row `timestamp`, never a literal.
class LogRecentRequest {
  const LogRecentRequest({
    required this.time,
    required this.name,
    required this.source,
    required this.meta,
    required this.resultLabel,
    required this.status,
  });

  final String time;
  final String name;

  final String source;

  final String meta;

  final String resultLabel;
  final LogRowStatus status;

  // Value equality lets an unchanged refresh skip rebuilding the cards.
  @override
  bool operator ==(Object other) =>
      other is LogRecentRequest &&
      other.time == time &&
      other.name == name &&
      other.source == source &&
      other.meta == meta &&
      other.resultLabel == resultLabel &&
      other.status == status;

  @override
  int get hashCode =>
      Object.hash(time, name, source, meta, resultLabel, status);
}

class LogCacheHotspot {
  const LogCacheHotspot({
    required this.queryName,
    required this.queryType,
    required this.remainingSeconds,
    required this.responseSize,
    required this.hitCount,
  });

  final String queryName;

  final String queryType;
  final int remainingSeconds;
  final int responseSize;
  final int hitCount;

  // Value equality lets an unchanged refresh skip rebuilding the cards.
  @override
  bool operator ==(Object other) =>
      other is LogCacheHotspot &&
      other.queryName == queryName &&
      other.queryType == queryType &&
      other.remainingSeconds == remainingSeconds &&
      other.responseSize == responseSize &&
      other.hitCount == hitCount;

  @override
  int get hashCode => Object.hash(
    queryName,
    queryType,
    remainingSeconds,
    responseSize,
    hitCount,
  );
}

class LogRaceWinner {
  const LogRaceWinner({
    required this.name,
    required this.wins,
    required this.averageElapsedMs,
  });

  final String name;
  final int wins;
  final double averageElapsedMs;

  // Value equality lets an unchanged refresh skip rebuilding the cards.
  @override
  bool operator ==(Object other) =>
      other is LogRaceWinner &&
      other.name == name &&
      other.wins == wins &&
      other.averageElapsedMs == averageElapsedMs;

  @override
  int get hashCode => Object.hash(name, wins, averageElapsedMs);
}

class LogBootstrapIp {
  const LogBootstrapIp({
    required this.name,
    required this.ip,
    required this.attempts,
    required this.successes,
    required this.averageElapsedMs,
  });

  final String name;
  final String ip;
  final int attempts;
  final int successes;
  final double averageElapsedMs;

  double get successRate => attempts == 0 ? 0 : successes / attempts;

  // Value equality lets an unchanged refresh skip rebuilding the cards.
  @override
  bool operator ==(Object other) =>
      other is LogBootstrapIp &&
      other.name == name &&
      other.ip == ip &&
      other.attempts == attempts &&
      other.successes == successes &&
      other.averageElapsedMs == averageElapsedMs;

  @override
  int get hashCode =>
      Object.hash(name, ip, attempts, successes, averageElapsedMs);
}

class LogSubscriptionBlock {
  const LogSubscriptionBlock({
    required this.name,
    required this.enabled,
    required this.deleted,
    required this.hits,
    required this.rate,
  });

  final String name;
  final bool enabled;

  final bool deleted;
  final int hits;

  final double rate;

  String get statusLabel {
    if (deleted) return currentL10n.subscriptionDeleted;
    return enabled ? currentL10n.commonEnabled : currentL10n.subscriptionDisabled;
  }

  // Value equality lets an unchanged refresh skip rebuilding the cards.
  @override
  bool operator ==(Object other) =>
      other is LogSubscriptionBlock &&
      other.name == name &&
      other.enabled == enabled &&
      other.deleted == deleted &&
      other.hits == hits &&
      other.rate == rate;

  @override
  int get hashCode => Object.hash(name, enabled, deleted, hits, rate);
}
