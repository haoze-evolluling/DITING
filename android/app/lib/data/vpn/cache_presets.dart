/// The three DNS cache presets. Each overwrites nine `dns_cache_*_v2` keys the engine reads
/// directly, so the UI must write exactly these values.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';

enum DnsCachePreset {
  conservative(
    storageValue: 'conservative',
    mode: 'follow_dns_ttl',
    maxTtlSeconds: 3600,
    fixedTtlSeconds: 3600,
    minTtlEnabled: false,
    minTtlSeconds: 60,
    staleFallbackEnabled: false,
    staleFallbackSeconds: 300,
  ),
  balanced(
    storageValue: 'balanced',
    mode: 'limit_max_ttl',
    maxTtlSeconds: 3600,
    fixedTtlSeconds: 3600,
    minTtlEnabled: true,
    minTtlSeconds: 60,
    staleFallbackEnabled: true,
    staleFallbackSeconds: 300,
  ),
  highHitRate(
    storageValue: 'high_hit_rate',
    mode: 'limit_max_ttl',
    maxTtlSeconds: 21600,
    fixedTtlSeconds: 3600,
    minTtlEnabled: true,
    minTtlSeconds: 120,
    staleFallbackEnabled: true,
    staleFallbackSeconds: 900,
  );

  const DnsCachePreset({
    required this.storageValue,
    required this.mode,
    required this.maxTtlSeconds,
    required this.fixedTtlSeconds,
    required this.minTtlEnabled,
    required this.minTtlSeconds,
    required this.staleFallbackEnabled,
    required this.staleFallbackSeconds,
  });

  String label(AppL10n l10n) => switch (this) {
    DnsCachePreset.conservative => l10n.cachePresetConservativeName,
    DnsCachePreset.balanced => l10n.cachePresetStandardName,
    DnsCachePreset.highHitRate => l10n.cachePresetAggressiveName,
  };

  String summary(AppL10n l10n) => switch (this) {
    DnsCachePreset.conservative => l10n.cachePresetConservativeSummary,
    DnsCachePreset.balanced => l10n.cachePresetStandardSummary,
    DnsCachePreset.highHitRate => l10n.cachePresetAggressiveSummary,
  };

  String description(AppL10n l10n) => switch (this) {
    DnsCachePreset.conservative => l10n.cachePresetConservativeDescription,
    DnsCachePreset.balanced => l10n.cachePresetStandardDescription,
    DnsCachePreset.highHitRate => l10n.cachePresetAggressiveDescription,
  };

  final String storageValue;
  final String mode;
  final int maxTtlSeconds;
  final int fixedTtlSeconds;
  final bool minTtlEnabled;
  final int minTtlSeconds;
  final bool staleFallbackEnabled;
  final int staleFallbackSeconds;

  static DnsCachePreset? fromStorage(String? value) {
    for (final preset in values) {
      if (preset.storageValue == value) return preset;
    }
    return null;
  }

  /// Derive a preset from the raw keys so installs predating `dns_cache_preset_v3` still show a
  /// sensible option.
  static DnsCachePreset fromPolicy(LegacySettings settings) {
    if (settings.cacheModeRaw == 'follow_dns_ttl' &&
        !settings.cacheMinTtlEnabled &&
        !settings.cacheStaleFallbackEnabled) {
      return conservative;
    }
    if (settings.cacheModeRaw == 'limit_max_ttl' &&
        settings.cacheMaxTtlSeconds <= balanced.maxTtlSeconds &&
        (!settings.cacheMinTtlEnabled ||
            settings.cacheMinTtlSeconds <= balanced.minTtlSeconds) &&
        (!settings.cacheStaleFallbackEnabled ||
            settings.cacheStaleFallbackSeconds <=
                balanced.staleFallbackSeconds)) {
      return balanced;
    }
    return highHitRate;
  }

  static DnsCachePreset current(LegacySettings settings) =>
      fromStorage(settings.cachePresetRaw) ?? fromPolicy(settings);

  void applyTo(LegacySettings settings, {required bool enabled}) {
    settings.applyCachePreset(
      storageValue: storageValue,
      enabled: enabled,
      mode: mode,
      maxTtlSeconds: maxTtlSeconds,
      fixedTtlSeconds: fixedTtlSeconds,
      minTtlEnabled: minTtlEnabled,
      minTtlSeconds: minTtlSeconds,
      staleFallbackEnabled: staleFallbackEnabled,
      staleFallbackSeconds: staleFallbackSeconds,
    );
  }
}

String cacheSummaryOf(LegacySettings settings) {
  if (!settings.cacheEnabled) return currentL10n.cacheDisabledSummary;
  final preset = DnsCachePreset.current(settings);
  return '${preset.label(currentL10n)} · ${preset.summary(currentL10n)}';
}
