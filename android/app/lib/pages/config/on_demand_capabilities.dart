library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_config_resources.dart';
import 'package:diting_android/data/native/battery_optimization.dart'
    show
        BatteryOptimizationState,
        platformChannelName,
        readBatteryOptimization,
        requestBatteryOptimization;
import 'package:diting_android/state/config_providers_resources.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _platformChannel = MethodChannel(platformChannelName);

String describeSsid(String? ssid, AppL10n l10n) => switch (ssid) {
  null => l10n.odCapNoPermission,
  '' => l10n.odPillNoWifi,
  final name => l10n.odCapCurrent(name),
};

final currentSsidReaderProvider = Provider<Future<String?> Function()>(
  (ref) => readCurrentSsid,
);

final currentSsidProvider = FutureProvider<String?>(
  (ref) => ref.watch(currentSsidReaderProvider)(),
);

final batteryOptimizationProvider = FutureProvider<BatteryOptimizationState>(
  (ref) => readBatteryOptimization(),
);

Future<String?> readCurrentSsid() async {
  try {
    return await _platformChannel.invokeMethod<String>('currentSsid');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

Future<BatteryOptimizationState> requestBatteryOptimizationAccess(
  WidgetRef ref,
) async {
  final state = await requestBatteryOptimization();
  ref.invalidate(batteryOptimizationProvider);
  return state;
}

enum SsidMatchState {
  disabled,

  unknown,

  noWifi,

  matched,

  unmatched,
}

class SsidDecision {
  const SsidDecision(this.state, [this.rule]);

  final SsidMatchState state;

  final MockSsidRule? rule;
}

final onDemandDecisionProvider = Provider<SsidDecision>((ref) {
  final resources = ref.watch(configResourcesProvider);
  return decideSsid(
    enabled: resources.onDemand,
    rules: resources.ssidRules,
    currentSsid: ref.watch(currentSsidProvider).asData?.value,
  );
});

SsidDecision decideSsid({
  required bool enabled,
  required List<MockSsidRule> rules,
  required String? currentSsid,
}) {
  if (!enabled) return const SsidDecision(SsidMatchState.disabled);
  if (currentSsid == null) return const SsidDecision(SsidMatchState.unknown);
  if (currentSsid.isEmpty) return const SsidDecision(SsidMatchState.noWifi);
  for (final rule in rules) {
    if (rule.ssid == currentSsid) {
      return SsidDecision(SsidMatchState.matched, rule);
    }
  }
  return const SsidDecision(SsidMatchState.unmatched);
}
