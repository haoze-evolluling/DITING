library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/prefs/config_resource_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/pages/config/on_demand_capabilities.dart';
import 'package:diting_android/state/config_providers_resources.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum OnDemandOutcome {
  disabled,

  unknownSsid,

  sameNetwork,

  noWifi,

  started,

  alreadyRunning,

  stopped,

  alreadyStopped,

  busy,

  needsConsent;

  String label(AppL10n l10n) => switch (this) {
    OnDemandOutcome.disabled => l10n.onDemandDisabled,
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

class OnDemandRunner {
  OnDemandRunner(this._ref);

  final Ref _ref;

  Future<OnDemandOutcome> apply({bool force = false}) async {
    final resources = _ref.read(configResourcesProvider);
    if (!resources.onDemand) {
      return OnDemandOutcome.disabled;
    }
    final ssid = await _ref.read(currentSsidReaderProvider)();
    if (ssid == null) {
      return OnDemandOutcome.unknownSsid;
    }
    final store = ConfigResourceStore(_ref.read(legacyPrefsStoreProvider));
    final lastSsid = store.loadLastEvaluatedSsid();
    if (!force && (lastSsid == ssid || lastSsid == null)) {
      if (lastSsid == null) store.saveLastEvaluatedSsid(ssid);
      return OnDemandOutcome.sameNetwork;
    }
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
        final rootStarting =
            after == PowerState.starting &&
            _ref.read(workModeProvider).hasTunnelFeatures &&
            _ref.read(rootDnsTakeoverProvider);
        return settle(
          after.isRunning || rootStarting
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
