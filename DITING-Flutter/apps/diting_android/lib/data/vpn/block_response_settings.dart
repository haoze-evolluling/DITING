/// Block response settings: the fixed mode in `block_response_mode` plus the dynamic policy keys
/// with hard clamps; `buildDnsConfig` publishes both.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';

enum BlockResponseMode {
  nxdomain('nxdomain'),
  nodata('nodata'),
  refused('refused'),
  zeroAddress('zero_address');

  const BlockResponseMode(this.storageValue);

  final String storageValue;

  String label(AppL10n l10n) => switch (this) {
    BlockResponseMode.nxdomain => l10n.blockResponseNxdomain,
    BlockResponseMode.nodata => l10n.blockResponseNodata,
    BlockResponseMode.refused => l10n.blockResponseRefused,
    BlockResponseMode.zeroAddress => l10n.blockResponseZeroAddress,
  };

  String description(AppL10n l10n) => switch (this) {
    BlockResponseMode.nxdomain => l10n.blockResponseNxdomainDescription,
    BlockResponseMode.nodata => l10n.blockResponseNodataDescription,
    BlockResponseMode.refused => l10n.blockResponseRefusedDescription,
    BlockResponseMode.zeroAddress => l10n.blockResponseZeroAddressDescription,
  };

  static BlockResponseMode fromStorage(String? value) {
    for (final mode in values) {
      if (mode.storageValue == value) return mode;
    }
    return nxdomain;
  }
}

class DynamicBlockPolicy {
  const DynamicBlockPolicy({
    required this.enabled,
    required this.requestThreshold,
    required this.windowSeconds,
    required this.nxDomainDurationSeconds,
  });

  final bool enabled;
  final int requestThreshold;
  final int windowSeconds;
  final int nxDomainDurationSeconds;

  static const defaults = DynamicBlockPolicy(
    enabled: false,
    requestThreshold: 5,
    windowSeconds: 60,
    nxDomainDurationSeconds: 300,
  );

  static DynamicBlockPolicy read(LegacySettings settings) => DynamicBlockPolicy(
    enabled: settings.dynamicBlockEnabled,
    requestThreshold: settings.dynamicBlockRequestThreshold,
    windowSeconds: settings.dynamicBlockWindowSeconds,
    nxDomainDurationSeconds: settings.dynamicBlockNxDomainDurationSeconds,
  );

  DynamicBlockPolicy copyWith({
    bool? enabled,
    int? requestThreshold,
    int? windowSeconds,
    int? nxDomainDurationSeconds,
  }) => DynamicBlockPolicy(
    enabled: enabled ?? this.enabled,
    requestThreshold: requestThreshold ?? this.requestThreshold,
    windowSeconds: windowSeconds ?? this.windowSeconds,
    nxDomainDurationSeconds:
        nxDomainDurationSeconds ?? this.nxDomainDurationSeconds,
  );

  void write(LegacySettings settings) => settings.setDynamicBlockPolicy(
    enabled: enabled,
    requestThreshold: requestThreshold,
    windowSeconds: windowSeconds,
    nxDurationSeconds: nxDomainDurationSeconds,
  );
}
