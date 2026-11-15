import 'package:diting_android/pages/health/health_score.dart';
import 'package:flutter_test/flutter_test.dart';

HealthInput _input({
  int granted = 2,
  int permTotal = 2,
  bool running = true,
  bool hasProvider = true,
  int totalRules = 1000,
  int failedSubs = 0,
  int totalSubs = 2,
  int queries = 1000,
  int cacheHits = 600,
  int blocked = 50,
}) => HealthInput(
  criticalPermissionsGranted: granted,
  criticalPermissionsTotal: permTotal,
  running: running,
  hasProvider: hasProvider,
  totalRules: totalRules,
  failedSubs: failedSubs,
  totalSubs: totalSubs,
  queries: queries,
  cacheHits: cacheHits,
  blocked: blocked,
);

void main() {
  test('a fully healthy setup scores high with no action items', () {
    final report = computeHealth(_input());
    expect(report.score, greaterThanOrEqualTo(80));
    expect(report.level, HealthSeverity.ok);
    expect(report.advices.single.id, 'allGood');
    expect(report.dimensions.length, 4);
  });

  test('missing permission and stopped tunnel surface critical actions', () {
    final report = computeHealth(_input(granted: 1, running: false));
    final ids = report.advices.map((a) => a.id).toList();
    expect(ids, contains('grantPermissions'));
    expect(ids, contains('startProtection'));
    // Those two are critical-severity actions even though other dimensions stay healthy.
    final start = report.advices.firstWhere((a) => a.id == 'startProtection');
    expect(start.severity, HealthSeverity.critical);
    expect(report.dimensions.firstWhere((d) => d.kind == HealthDimensionKind.dns).score, 25);
  });

  test('no rules tanks the filter dimension and adds import advice', () {
    final report = computeHealth(_input(totalRules: 0, totalSubs: 0));
    final filter = report.dimensions.firstWhere(
      (d) => d.kind == HealthDimensionKind.filter,
    );
    expect(filter.score, 20);
    expect(report.advices.map((a) => a.id), contains('importRules'));
  });

  test('failed subscriptions lower the filter score', () {
    final healthy = computeHealth(_input(failedSubs: 0)).dimensions.firstWhere(
      (d) => d.kind == HealthDimensionKind.filter,
    );
    final degraded = computeHealth(_input(failedSubs: 2)).dimensions.firstWhere(
      (d) => d.kind == HealthDimensionKind.filter,
    );
    expect(degraded.score, lessThan(healthy.score));
  });

  test('low cache hit rate adds the cache advice', () {
    final report = computeHealth(_input(queries: 200, cacheHits: 10));
    expect(report.advices.map((a) => a.id), contains('lowCache'));
  });

  test('no blocking despite traffic adds the no-blocking advice', () {
    final report = computeHealth(_input(queries: 500, blocked: 0));
    expect(report.advices.map((a) => a.id), contains('noBlocking'));
  });
}
