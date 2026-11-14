/// U5 / U6: pure aggregation of the live `flow-core` snapshot into per-app report cards and a
/// connection map. Aggregation is a display decision, not a kernel one, so it stays in Dart; nothing
/// here talks to the network or the platform.
library;

import 'package:diting_android/data/native/flow_bridge.dart';

/// One domain's slice inside an app report.
class DomainSummary {
  const DomainSummary({
    required this.domain,
    required this.connectionCount,
    required this.totalBytes,
    required this.blockedCount,
  });

  final String domain;
  final int connectionCount;
  final int totalBytes;
  final int blockedCount;

  bool get blocked => blockedCount > 0;
}

/// U5 应用报告卡：one app's connection / block / traffic summary.
class AppReport {
  const AppReport({
    required this.appLabel,
    required this.connectionCount,
    required this.blockedCount,
    required this.upBytes,
    required this.downBytes,
    required this.topDomains,
  });

  final String appLabel;
  final int connectionCount;
  final int blockedCount;
  final int upBytes;
  final int downBytes;

  /// Busiest domains, capped at three.
  final List<DomainSummary> topDomains;

  int get totalBytes => upBytes + downBytes;

  bool get hasBlocked => blockedCount > 0;

  /// The block share, 0..1, rounded for a progress bar.
  double get blockedRatio =>
      connectionCount == 0 ? 0 : blockedCount / connectionCount;
}

/// U6 连接地图：one app's domains (each with the remote endpoints behind it).
class AppConnectionGroup {
  const AppConnectionGroup({required this.appLabel, required this.domains});

  final String appLabel;
  final List<DomainSummary> domains;
}

/// `true` when the flow is a block (`failed`), matching the live-flow tile's own rule.
bool _isBlocked(FlowRow row) => row.status == 'failed';

/// Groups rows by app, aggregating counts and bytes.
Map<String, List<FlowRow>> _byApp(List<FlowRow> rows) {
  final groups = <String, List<FlowRow>>{};
  for (final row in rows) {
    groups.putIfAbsent(row.appLabel, () => []).add(row);
  }
  return groups;
}

/// Aggregates one app's rows into a [DomainSummary] list, busiest first.
List<DomainSummary> _domainsOf(List<FlowRow> rows) {
  final byDomain = <String, List<FlowRow>>{};
  for (final row in rows) {
    byDomain.putIfAbsent(row.hostLabel, () => []).add(row);
  }
  final summaries = [
    for (final entry in byDomain.entries)
      DomainSummary(
        domain: entry.key,
        connectionCount: entry.value.length,
        totalBytes: entry.value.fold(
          0,
          (sum, row) => sum + row.upBytes + row.downBytes,
        ),
        blockedCount: entry.value.where(_isBlocked).length,
      ),
  ];
  summaries.sort((a, b) {
    final byBytes = b.totalBytes.compareTo(a.totalBytes);
    if (byBytes != 0) return byBytes;
    return a.domain.compareTo(b.domain);
  });
  return summaries;
}

/// U5: one report card per app, busiest first.
List<AppReport> buildAppReports(List<FlowRow> rows) {
  final reports = <AppReport>[];
  for (final entry in _byApp(rows).entries) {
    final appRows = entry.value;
    final domains = _domainsOf(appRows);
    reports.add(
      AppReport(
        appLabel: entry.key,
        connectionCount: appRows.length,
        blockedCount: appRows.where(_isBlocked).length,
        upBytes: appRows.fold(0, (sum, row) => sum + row.upBytes),
        downBytes: appRows.fold(0, (sum, row) => sum + row.downBytes),
        topDomains: domains.take(3).toList(),
      ),
    );
  }
  reports.sort((a, b) {
    final byBytes = b.totalBytes.compareTo(a.totalBytes);
    if (byBytes != 0) return byBytes;
    return a.appLabel.compareTo(b.appLabel);
  });
  return reports;
}

/// U6: the app → domain connection map, apps and domains ordered stably.
List<AppConnectionGroup> buildConnectionMap(List<FlowRow> rows) {
  final groups = <AppConnectionGroup>[];
  for (final entry in _byApp(rows).entries) {
    groups.add(
      AppConnectionGroup(
        appLabel: entry.key,
        domains: _domainsOf(entry.value),
      ),
    );
  }
  groups.sort((a, b) => a.appLabel.compareTo(b.appLabel));
  return groups;
}
