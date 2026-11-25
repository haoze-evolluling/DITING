library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';

enum DnsCacheTier {
  conservative('conservative', 50),
  standard('standard', 100),
  aggressive('aggressive', 200),
  custom('custom', 100);

  const DnsCacheTier(this.storageValue, this.defaultScalePercent);

  final String storageValue;
  final int defaultScalePercent;

  bool get isCustom => this == DnsCacheTier.custom;

  String label(AppL10n l10n) => switch (this) {
    DnsCacheTier.conservative => l10n.cachePresetConservativeName,
    DnsCacheTier.standard => l10n.cachePresetStandardName,
    DnsCacheTier.aggressive => l10n.cachePresetAggressiveName,
    DnsCacheTier.custom => l10n.cachePresetCustomName,
  };

  String summary(AppL10n l10n) => switch (this) {
    DnsCacheTier.conservative => l10n.cachePresetConservativeSummary,
    DnsCacheTier.standard => l10n.cachePresetStandardSummary,
    DnsCacheTier.aggressive => l10n.cachePresetAggressiveSummary,
    DnsCacheTier.custom => l10n.cachePresetCustomSummary,
  };

  static DnsCacheTier? fromStorage(String? value) => switch (value) {
    'conservative' => DnsCacheTier.conservative,
    'standard' => DnsCacheTier.standard,
    'aggressive' => DnsCacheTier.aggressive,
    'custom' => DnsCacheTier.custom,
    _ => null,
  };
}

class DnsCachePolicy {
  const DnsCachePolicy({required this.tier, required this.scalePercent});

  final DnsCacheTier tier;
  final int scalePercent;

  static const int minScalePercent = 10;
  static const int maxScalePercent = 500;
  static const int scaleStepPercent = 10;
  static const int maxTtlSeconds = 86400;
  static const int staleFallbackSeconds = 300;
  static const int sampleUpstreamSeconds = 300;

  static int clampScale(int percent) {
    final rounded = (percent / scaleStepPercent).round() * scaleStepPercent;
    return rounded.clamp(minScalePercent, maxScalePercent);
  }

  static int effectiveTtl(int upstreamSeconds, int scalePercent) {
    final scaled = (upstreamSeconds * clampScale(scalePercent) + 50) ~/ 100;
    return scaled.clamp(0, maxTtlSeconds);
  }

  static DnsCachePolicy read(LegacySettings settings) {
    final stored = DnsCacheTier.fromStorage(settings.cachePresetV4);
    if (stored == null) {
      return const DnsCachePolicy(
        tier: DnsCacheTier.standard,
        scalePercent: 100,
      );
    }
    if (!stored.isCustom) {
      return DnsCachePolicy(
        tier: stored,
        scalePercent: stored.defaultScalePercent,
      );
    }
    return DnsCachePolicy(
      tier: DnsCacheTier.custom,
      scalePercent: clampScale(settings.cacheScalePercentV4 ?? 100),
    );
  }

  void write(LegacySettings settings, {required bool enabled}) {
    settings.writeCachePolicy(
      enabled: enabled,
      preset: tier.storageValue,
      scalePercent: tier.isCustom
          ? clampScale(scalePercent)
          : tier.defaultScalePercent,
    );
  }
}

String formatCacheScale(int percent) {
  final clamped = DnsCachePolicy.clampScale(percent);
  if (clamped % 100 == 0) return '${clamped ~/ 100}';
  return (clamped / 100).toStringAsFixed(1);
}

String cachePresetExampleText(AppL10n l10n, int scalePercent) {
  final cached = DnsCachePolicy.effectiveTtl(
    DnsCachePolicy.sampleUpstreamSeconds,
    scalePercent,
  );
  return l10n.cachePresetExample(DnsCachePolicy.sampleUpstreamSeconds, cached);
}

String cachePolicySummary(LegacySettings settings, AppL10n l10n) {
  final policy = DnsCachePolicy.read(settings);
  return '${policy.tier.label(l10n)} · '
      '${l10n.cachePresetMultiplier(formatCacheScale(policy.scalePercent))}';
}
