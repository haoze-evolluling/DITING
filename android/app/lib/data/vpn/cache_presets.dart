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
  highHitRate('high_hit_rate'),
  custom('custom');

  const DnsCachePreset(this.storageValue);

  /// The prefs spelling; the declaration order is the kernel's preset index.
  final String storageValue;

  String label(AppL10n l10n) => switch (this) {
    DnsCachePreset.conservative => l10n.cachePresetConservativeName,
    DnsCachePreset.balanced => l10n.cachePresetStandardName,
    DnsCachePreset.highHitRate => l10n.cachePresetAggressiveName,
    DnsCachePreset.custom => l10n.cachePresetCustomName,
  };

  String summary(AppL10n l10n) => switch (this) {
    DnsCachePreset.conservative => l10n.cachePresetConservativeSummary,
    DnsCachePreset.balanced => l10n.cachePresetStandardSummary,
    DnsCachePreset.highHitRate => l10n.cachePresetAggressiveSummary,
    DnsCachePreset.custom => l10n.cachePresetCustomSummary,
  };

  String description(AppL10n l10n) => switch (this) {
    DnsCachePreset.conservative => l10n.cachePresetConservativeDescription,
    DnsCachePreset.balanced => l10n.cachePresetStandardDescription,
    DnsCachePreset.highHitRate => l10n.cachePresetAggressiveDescription,
    DnsCachePreset.custom => l10n.cachePresetCustomDescription,
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

  static DnsCachePreset current(LegacySettings settings) {
    // The kernel has no custom entry; the marker lives only in the prefs, and the raw values
    // behind it are read by [DnsCacheCustomPolicy].
    if (settings.cachePresetRaw == DnsCachePreset.custom.storageValue) {
      return DnsCachePreset.custom;
    }
    return values[RustDnsConfigCore.instance.currentCachePreset(
      settings.cachePresetRaw,
      mode: settings.cacheModeRaw,
      maxTtlSeconds: settings.cacheMaxTtlSeconds,
      minTtlEnabled: settings.cacheMinTtlEnabled,
      minTtlSeconds: settings.cacheMinTtlSeconds,
      staleFallbackEnabled: settings.cacheStaleFallbackEnabled,
      staleFallbackSeconds: settings.cacheStaleFallbackSeconds,
    )];
  }

  void applyTo(LegacySettings settings, {required bool enabled}) {
    // Custom keeps whatever the user already tuned; only the marker and enable flag change.
    if (this == DnsCachePreset.custom) {
      DnsCacheCustomPolicy.read(settings).write(settings, enabled: enabled);
      return;
    }
    final preset = RustDnsConfigCore.instance.presetValues(index);
    settings.applyCachePreset(
      storageValue: storageValue,
      enabled: enabled,
      mode: preset.mode,
      maxTtlSeconds: preset.maxTtlSeconds,
      fixedTtlSeconds: preset.fixedTtlSeconds,
      minTtlEnabled: preset.minTtlEnabled,
      minTtlSeconds: preset.minTtlSeconds,
      staleFallbackEnabled: preset.staleFallbackEnabled,
      staleFallbackSeconds: preset.staleFallbackSeconds,
    );
  }
}

/// The nine raw keys behind [DnsCachePreset.custom], exposed as editable values.
///
/// The engine accepts `follow_dns_ttl` / `limit_max_ttl` / `fixed_ttl`; every duration is clamped
/// to 30–86400 seconds when written, matching `LegacySettings.applyCachePreset`.
class DnsCacheCustomPolicy {
  const DnsCacheCustomPolicy({
    required this.mode,
    required this.maxTtlSeconds,
    required this.fixedTtlSeconds,
    required this.minTtlEnabled,
    required this.minTtlSeconds,
    required this.staleFallbackEnabled,
    required this.staleFallbackSeconds,
  });

  static const int minSeconds = 30;
  static const int maxSeconds = 86400;

  static const String modeFollow = 'follow_dns_ttl';
  static const String modeLimitMax = 'limit_max_ttl';
  static const String modeFixed = 'fixed_ttl';

  static const List<String> modes = [modeFollow, modeLimitMax, modeFixed];

  final String mode;
  final int maxTtlSeconds;
  final int fixedTtlSeconds;
  final bool minTtlEnabled;
  final int minTtlSeconds;
  final bool staleFallbackEnabled;
  final int staleFallbackSeconds;

  factory DnsCacheCustomPolicy.read(LegacySettings settings) =>
      DnsCacheCustomPolicy(
        mode: modes.contains(settings.cacheModeRaw)
            ? settings.cacheModeRaw
            : modeLimitMax,
        maxTtlSeconds: settings.cacheMaxTtlSeconds,
        fixedTtlSeconds: settings.cacheFixedTtlSeconds,
        minTtlEnabled: settings.cacheMinTtlEnabled,
        minTtlSeconds: settings.cacheMinTtlSeconds,
        staleFallbackEnabled: settings.cacheStaleFallbackEnabled,
        staleFallbackSeconds: settings.cacheStaleFallbackSeconds,
      );

  DnsCacheCustomPolicy copyWith({
    String? mode,
    int? maxTtlSeconds,
    int? fixedTtlSeconds,
    bool? minTtlEnabled,
    int? minTtlSeconds,
    bool? staleFallbackEnabled,
    int? staleFallbackSeconds,
  }) => DnsCacheCustomPolicy(
    mode: mode ?? this.mode,
    maxTtlSeconds: maxTtlSeconds ?? this.maxTtlSeconds,
    fixedTtlSeconds: fixedTtlSeconds ?? this.fixedTtlSeconds,
    minTtlEnabled: minTtlEnabled ?? this.minTtlEnabled,
    minTtlSeconds: minTtlSeconds ?? this.minTtlSeconds,
    staleFallbackEnabled: staleFallbackEnabled ?? this.staleFallbackEnabled,
    staleFallbackSeconds: staleFallbackSeconds ?? this.staleFallbackSeconds,
  );

  void write(LegacySettings settings, {required bool enabled}) =>
      settings.applyCachePreset(
        storageValue: DnsCachePreset.custom.storageValue,
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

String cacheCustomModeLabel(AppL10n l10n, String mode) => switch (mode) {
  DnsCacheCustomPolicy.modeFollow => l10n.cacheCustomModeFollow,
  DnsCacheCustomPolicy.modeFixed => l10n.cacheCustomModeFixed,
  _ => l10n.cacheCustomModeLimit,
};

String cacheCustomModeDescription(AppL10n l10n, String mode) => switch (mode) {
  DnsCacheCustomPolicy.modeFollow => l10n.cacheCustomModeFollowDesc,
  DnsCacheCustomPolicy.modeFixed => l10n.cacheCustomModeFixedDesc,
  _ => l10n.cacheCustomModeLimitDesc,
};

String cacheSummaryOf(LegacySettings settings) {
  if (!settings.cacheEnabled) return currentL10n.cacheDisabledSummary;
  return cachePolicySummary(settings, currentL10n);
}

/// The one-line policy description used by the switch and by `cacheSummaryOf`.
String cachePolicySummary(LegacySettings settings, AppL10n l10n) {
  final preset = DnsCachePreset.current(settings);
  if (preset != DnsCachePreset.custom) {
    return '${preset.label(l10n)} · ${preset.summary(l10n)}';
  }
  final policy = DnsCacheCustomPolicy.read(settings);
  final parts = <String>[
    switch (policy.mode) {
      DnsCacheCustomPolicy.modeFollow => l10n.cacheCustomModeFollow,
      DnsCacheCustomPolicy.modeFixed => l10n.cacheCustomSummaryFixed(
        formatCacheSeconds(l10n, policy.fixedTtlSeconds),
      ),
      _ => l10n.cacheCustomSummaryMax(
        formatCacheSeconds(l10n, policy.maxTtlSeconds),
      ),
    },
    if (policy.minTtlEnabled)
      l10n.cacheCustomSummaryMin(
        formatCacheSeconds(l10n, policy.minTtlSeconds),
      ),
    if (policy.staleFallbackEnabled)
      l10n.cacheCustomSummaryStale(
        formatCacheSeconds(l10n, policy.staleFallbackSeconds),
      ),
  ];
  return '${preset.label(l10n)} · ${parts.join(' · ')}';
}

/// Whole hours and minutes where possible, otherwise seconds; keeps custom values readable
/// without another per-field formatter.
String formatCacheSeconds(AppL10n l10n, int seconds) {
  if (seconds >= 3600 && seconds % 3600 == 0) {
    return l10n.cacheDurationHours(seconds ~/ 3600);
  }
  if (seconds >= 60 && seconds % 60 == 0) {
    return l10n.cacheDurationMinutes(seconds ~/ 60);
  }
  return l10n.cacheDurationSeconds(seconds);
}
