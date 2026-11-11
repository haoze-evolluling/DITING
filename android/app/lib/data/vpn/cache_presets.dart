/// The three DNS cache presets. Each overwrites nine `dns_cache_*_v2` keys the engine reads
/// directly, so the UI must write exactly these values.
///
/// The numbers and the derivation from raw keys live in
/// `rust/diting-dns-config-core/src/presets.rs`; only the labels are localised here.
library;

import 'package:diting_android/data/vpn/rust_dns_config_core.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';

enum DnsCachePreset {
  conservative('conservative'),
  balanced('balanced'),
  highHitRate('high_hit_rate');

  const DnsCachePreset(this.storageValue);

  /// The prefs spelling; the declaration order is the kernel's preset index.
  final String storageValue;

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

  static DnsCachePreset? fromStorage(String? value) {
    for (final preset in values) {
      if (preset.storageValue == value) return preset;
    }
    return null;
  }

  /// Derive a preset from the raw keys so installs predating `dns_cache_preset_v3` still show a
  /// sensible option.
  static DnsCachePreset fromPolicy(LegacySettings settings) =>
      values[RustDnsConfigCore.instance.cachePresetFromPolicy(
        mode: settings.cacheModeRaw,
        maxTtlSeconds: settings.cacheMaxTtlSeconds,
        minTtlEnabled: settings.cacheMinTtlEnabled,
        minTtlSeconds: settings.cacheMinTtlSeconds,
        staleFallbackEnabled: settings.cacheStaleFallbackEnabled,
        staleFallbackSeconds: settings.cacheStaleFallbackSeconds,
      )];

  static DnsCachePreset current(LegacySettings settings) =>
      values[RustDnsConfigCore.instance.currentCachePreset(
        settings.cachePresetRaw,
        mode: settings.cacheModeRaw,
        maxTtlSeconds: settings.cacheMaxTtlSeconds,
        minTtlEnabled: settings.cacheMinTtlEnabled,
        minTtlSeconds: settings.cacheMinTtlSeconds,
        staleFallbackEnabled: settings.cacheStaleFallbackEnabled,
        staleFallbackSeconds: settings.cacheStaleFallbackSeconds,
      )];

  void applyTo(LegacySettings settings, {required bool enabled}) {
    final values = RustDnsConfigCore.instance.presetValues(index);
    settings.applyCachePreset(
      storageValue: storageValue,
      enabled: enabled,
      mode: values.mode,
      maxTtlSeconds: values.maxTtlSeconds,
      fixedTtlSeconds: values.fixedTtlSeconds,
      minTtlEnabled: values.minTtlEnabled,
      minTtlSeconds: values.minTtlSeconds,
      staleFallbackEnabled: values.staleFallbackEnabled,
      staleFallbackSeconds: values.staleFallbackSeconds,
    );
  }
}

String cacheSummaryOf(LegacySettings settings) {
  if (!settings.cacheEnabled) return currentL10n.cacheDisabledSummary;
  final preset = DnsCachePreset.current(settings);
  return '${preset.label(currentL10n)} · ${preset.summary(currentL10n)}';
}
