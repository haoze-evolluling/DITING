/// Applies the on-demand whitelist to the live tunnel.
///
/// The switch and the SSID table are persisted configuration; without this runner they were only
/// ever displayed. There is no background network callback in this build (the platform channel
/// reports the joined SSID on demand), so the catch-up moments are start and resume — but the
/// whitelist only moves the tunnel when the network CHANGED since the last evaluation. Re-running
/// the same network would override a manual start/stop on every launch, which is why the last
/// evaluated SSID is persisted next to the rules.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/prefs/config_resource_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/pages/config/on_demand_capabilities.dart';
import 'package:diting_android/state/config_providers_resources.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What one evaluation did, so the page can say why nothing happened.
enum OnDemandOutcome {
  /// The on-demand switch is off; the tunnel is left to the power button.
  disabled,

  /// Server mode owns its own service; the tunnel whitelist does not apply.
  serverMode,

  /// The platform could not report the network, so the whitelist cannot be trusted.
  unknownSsid,

  /// The network is the one the whitelist was last applied to; a manual start or stop is kept.
  sameNetwork,

  /// Not on Wi-Fi and no whitelist entry covers cellular.
  noWifi,

  /// Matched an entry, so the tunnel was (or already is) running.
  started,

  /// Already running for a matching network; nothing to change.
  alreadyRunning,

  /// Did not match, so a running tunnel was stopped.
  stopped,

  /// Did not match and nothing was running.
  alreadyStopped,

  /// The tunnel is mid-transition; the next evaluation picks it up.
  busy,

  /// The whitelist matched but the system dialog has not been accepted yet.
  needsConsent;

  String label(AppL10n l10n) => switch (this) {
    OnDemandOutcome.disabled => l10n.onDemandDisabled,
    OnDemandOutcome.serverMode => l10n.onDemandServerMode,
    OnDemandOutcome.unknownSsid => l10n.onDemandUnknownSsid,
    OnDemandOutcome.sameNetwork => l10n.onDemandSameNetwork,
    OnDemandOutcome.noWifi => l10n.onDemandNoWifi,
    OnDemandOutcome.started => l10n.onDemandStarted,
    OnDemandOutcome.alreadyRunning => l10n.onDemandAlreadyRunning,
    OnDemandOutcome.stopped => l10n.onDemandStopped,
    OnDemandOutcome.alreadyStopped => l10n.onDemandAlreadyStopped,
    OnDemandOutcome.busy => l10n.onDemandBusy,
    OnDemandOutcome.needsConsent => l10n.onDemandNeedsConsent,
  };
}

/// Re-evaluates the whitelist against the network the device is on now and moves the tunnel to
/// match it.
class OnDemandRunner {
  OnDemandRunner(this._ref);

  final Ref _ref;

  /// [force] re-evaluates even when the network is unchanged; the "立即应用" button and the
  /// on-demand switch use it, start and resume do not.
  Future<OnDemandOutcome> apply({bool force = false}) async {
    final resources = _ref.read(configResourcesProvider);
    if (!resources.onDemand) {
      return OnDemandOutcome.disabled;
    }
    // Server mode runs the LAN DNS service instead of the tunnel, so there is nothing to switch.
    if (_ref.read(workModeProvider) == AppWorkMode.server) {
      return OnDemandOutcome.serverMode;
    }
    // Read the SSID fresh: the cached provider may describe the network from before a switch.
    final ssid = await _ref.read(currentSsidReaderProvider)();
    if (ssid == null) {
      return OnDemandOutcome.unknownSsid;
    }
    final store = ConfigResourceStore(_ref.read(legacyPrefsStoreProvider));
    final lastSsid = store.loadLastEvaluatedSsid();
    // A never-evaluated install only records the network, so an upgrade cannot auto-start the
    // tunnel; after that, acting is reserved for a real network change.
    if (!force && (lastSsid == ssid || lastSsid == null)) {
      if (lastSsid == null) store.saveLastEvaluatedSsid(ssid);
      return OnDemandOutcome.sameNetwork;
    }
    // Only a settled outcome records the network; `busy` retries on the next evaluation.
    OnDemandOutcome settle(OnDemandOutcome outcome) {
      if (outcome != OnDemandOutcome.busy) {
        store.saveLastEvaluatedSsid(ssid);
      }
      return outcome;
    }

    final decision = decideSsid(
      enabled: true,
      rules: resources.ssidRules,
      currentSsid: ssid,
    );
    final power = _ref.read(powerProvider);
    switch (decision.state) {
      case SsidMatchState.disabled:
        return OnDemandOutcome.disabled;
      case SsidMatchState.unknown:
        return OnDemandOutcome.unknownSsid;
      case SsidMatchState.matched:
        if (power.isRunning) {
          return settle(OnDemandOutcome.alreadyRunning);
        }
        if (power.isBusy) {
          return OnDemandOutcome.busy;
        }
        await _ref.read(powerProvider.notifier).toggle();
        final after = _ref.read(powerProvider);
        // `toggle` returns once the start is scheduled; `starting` means the system consent
        // dialog is still open and the real answer arrives through `onPrepareResult`.
        return settle(
          after.isRunning
              ? OnDemandOutcome.started
              : OnDemandOutcome.needsConsent,
        );
      case SsidMatchState.noWifi:
      case SsidMatchState.unmatched:
        if (!power.isRunning) {
          return settle(OnDemandOutcome.alreadyStopped);
        }
        if (power.isBusy) {
          return OnDemandOutcome.busy;
        }
        await _ref.read(powerProvider.notifier).stop();
        return settle(OnDemandOutcome.stopped);
    }
  }
}

final onDemandRunnerProvider = Provider<OnDemandRunner>(OnDemandRunner.new);
