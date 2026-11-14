/// U1 保护健康评分 + Advisor 的纯计算核心。
///
/// 把「权限 / DNS / 过滤器 / 缓存」四个维度的现状聚合成一个 0–100 分，并给出下一步建议。
/// 纯函数、无 IO：数据由 `health_providers.dart` 采集后传入，因此可以脱离设备单测。
library;

/// 四个评分维度。
enum HealthDimensionKind { permissions, dns, filter, cache }

/// 严重度，同时用于配色与建议排序。
enum HealthSeverity { ok, warning, critical }

/// 单个维度的分数（0–100）。
class HealthDimension {
  const HealthDimension({required this.kind, required this.score});

  final HealthDimensionKind kind;
  final int score;
}

/// 一条建议；[id] 是本地化键后缀，页面负责翻译。
class HealthAdvice {
  const HealthAdvice({required this.id, required this.severity});

  final String id;
  final HealthSeverity severity;
}

class HealthReport {
  const HealthReport({
    required this.score,
    required this.level,
    required this.dimensions,
    required this.advices,
  });

  final int score;
  final HealthSeverity level;
  final List<HealthDimension> dimensions;
  final List<HealthAdvice> advices;

  bool get isHealthy => level == HealthSeverity.ok;
}

/// 采集到的原始指标。
class HealthInput {
  const HealthInput({
    required this.criticalPermissionsGranted,
    required this.criticalPermissionsTotal,
    required this.running,
    required this.hasProvider,
    required this.totalRules,
    required this.failedSubs,
    required this.totalSubs,
    required this.queries,
    required this.cacheHits,
    required this.blocked,
  });

  final int criticalPermissionsGranted;
  final int criticalPermissionsTotal;
  final bool running;
  final bool hasProvider;
  final int totalRules;
  final int failedSubs;
  final int totalSubs;
  final int queries;
  final int cacheHits;
  final int blocked;
}

int _clamp(int value) => value < 0 ? 0 : (value > 100 ? 100 : value);

/// 计算评分与建议。四个维度等权，避免把某一项调得过重而误伤整体感官。
HealthReport computeHealth(HealthInput input) {
  // 权限
  final permTotal = input.criticalPermissionsTotal;
  final permScore = permTotal == 0
      ? 100
      : _clamp((input.criticalPermissionsGranted * 100 / permTotal).round());

  // DNS：未运行 → 低；运行但无上游 → 中；运行且有上游 → 高。
  final int dnsScore;
  if (!input.running) {
    dnsScore = 25;
  } else if (!input.hasProvider) {
    dnsScore = 55;
  } else {
    dnsScore = 90;
  }

  // 过滤器：有规则才有基础分；失败订阅按比例扣分。
  final int filterScore;
  if (input.totalRules <= 0) {
    filterScore = 20;
  } else {
    final failRatio = input.totalSubs == 0
        ? 0.0
        : input.failedSubs / input.totalSubs;
    filterScore = _clamp((90 - failRatio * 60).round());
  }

  // 缓存：有流量时按命中率；无流量给中性 60。
  final int cacheScore;
  if (input.queries <= 0) {
    cacheScore = 60;
  } else {
    cacheScore = _clamp((input.cacheHits * 100 / input.queries).round());
  }

  final dimensions = [
    HealthDimension(kind: HealthDimensionKind.permissions, score: permScore),
    HealthDimension(kind: HealthDimensionKind.dns, score: dnsScore),
    HealthDimension(kind: HealthDimensionKind.filter, score: filterScore),
    HealthDimension(kind: HealthDimensionKind.cache, score: cacheScore),
  ];
  final overall = _clamp(
    (permScore + dnsScore + filterScore + cacheScore) ~/ 4,
  );
  final level = overall >= 80
      ? HealthSeverity.ok
      : (overall >= 55 ? HealthSeverity.warning : HealthSeverity.critical);

  final advices = <HealthAdvice>[];
  if (permScore < 100) {
    advices.add(
      const HealthAdvice(
        id: 'grantPermissions',
        severity: HealthSeverity.critical,
      ),
    );
  }
  if (!input.running) {
    advices.add(
      const HealthAdvice(id: 'startProtection', severity: HealthSeverity.critical),
    );
  }
  if (input.totalRules <= 0) {
    advices.add(
      const HealthAdvice(id: 'importRules', severity: HealthSeverity.warning),
    );
  }
  if (input.failedSubs > 0) {
    advices.add(
      const HealthAdvice(
        id: 'updateSubscriptions',
        severity: HealthSeverity.warning,
      ),
    );
  }
  if (input.queries > 50) {
    final rate = input.cacheHits / input.queries;
    if (rate < 0.3) {
      advices.add(
        const HealthAdvice(id: 'lowCache', severity: HealthSeverity.warning),
      );
    }
  }
  if (input.queries > 100 && input.blocked == 0) {
    advices.add(
      const HealthAdvice(id: 'noBlocking', severity: HealthSeverity.warning),
    );
  }
  if (advices.isEmpty) {
    advices.add(const HealthAdvice(id: 'allGood', severity: HealthSeverity.ok));
  }

  return HealthReport(
    score: overall,
    level: level,
    dimensions: dimensions,
    advices: advices,
  );
}
