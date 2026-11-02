/// Platform capabilities the on-demand page reports: the Wi-Fi name the device is joined to and
/// the battery-optimization allowlist. Both degrade to an explicit "unavailable" state instead of
/// claiming a value, because neither can be answered without a native channel.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_config_resources.dart';
import 'package:diting_android/pages/server/server_platform_probe.dart'
    show
        BatteryOptimizationState,
        platformChannelName,
        readBatteryOptimization,
        requestBatteryOptimization;
import 'package:diting_android/state/config_providers_resources.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _platformChannel = MethodChannel(platformChannelName);

/// Reads the SSID of the joined Wi-Fi.
///
/// An empty string means "not on Wi-Fi"; null means the channel answered nothing — the method is
/// not implemented yet or the location permission is missing, and the page says so instead of
/// showing a made-up name.
String describeSsid(String? ssid, AppL10n l10n) => switch (ssid) {
  null => l10n.odCapNoPermission,
  '' => l10n.odPillNoWifi,
  final name => l10n.odCapCurrent(name),
};

/// Reads the joined Wi-Fi name; injected so tests can answer without a platform channel.
final currentSsidReaderProvider = Provider<Future<String?> Function()>(
  (ref) => readCurrentSsid,
);

/// Current Wi-Fi name; a page open re-reads it, since the network can change in between.
final currentSsidProvider = FutureProvider<String?>(
  (ref) => ref.watch(currentSsidReaderProvider)(),
);

/// Battery-optimization allowlist state; watching it is what makes the row show a real value.
final batteryOptimizationProvider = FutureProvider<BatteryOptimizationState>(
  (ref) => readBatteryOptimization(),
);

/// The `currentSsid` method on the legacy `platform` channel: null means the name cannot be read
/// (no location permission, or a build without the channel), `''` means the device is not on Wi-Fi.
Future<String?> readCurrentSsid() async {
  try {
    return await _platformChannel.invokeMethod<String>('currentSsid');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// Opens the system allowlist prompt and re-reads the state afterwards, because the native reply
/// only means the settings page opened — cancelling it leaves the app not allowlisted.
Future<BatteryOptimizationState> requestBatteryOptimizationAccess(
  WidgetRef ref,
) async {
  final state = await requestBatteryOptimization();
  ref.invalidate(batteryOptimizationProvider);
  return state;
}

/// Why the on-demand switch would or would not start the tunnel right now.
enum SsidMatchState {
  /// The on-demand switch is off, so the whitelist is not consulted.
  disabled,

  /// The platform could not report the current network.
  unknown,

  /// Not joined to any Wi-Fi.
  noWifi,

  /// The joined network is in the whitelist.
  matched,

  /// The joined network is not in the whitelist.
  unmatched,
}

/// The outcome of evaluating the whitelist against the current network.
class SsidDecision {
  const SsidDecision(this.state, [this.rule]);

  final SsidMatchState state;

  /// The rule that matched, for showing its delay and connection kinds.
  final MockSsidRule? rule;
}

/// The rule table applied to the network the device is on now. This is what reads the persisted
/// whitelist back: without it the list would only ever be written and displayed.
final onDemandDecisionProvider = Provider<SsidDecision>((ref) {
  final resources = ref.watch(configResourcesProvider);
  return decideSsid(
    enabled: resources.onDemand,
    rules: resources.ssidRules,
    currentSsid: ref.watch(currentSsidProvider).asData?.value,
  );
});

/// Pure so the page and the tests agree on the rule: the whitelist only starts the tunnel when the
/// switch is on and the joined SSID matches one entry. SSIDs are case-sensitive, as on Android.
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
