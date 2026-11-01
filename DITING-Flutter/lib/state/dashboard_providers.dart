/// Live dashboard data: speed series, traffic totals and core state; polling is explicit so tests
/// can settle.
library;

import 'dart:async';

import 'package:diting/data/dashboard_models.dart';
import 'package:diting/data/vpn/vpn_bridge.dart';
import 'package:diting/state/server_status_providers.dart';
import 'package:diting/state/traffic_providers.dart';
import 'package:diting/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Callers of this library keep getting the board layout from one place.
export 'package:diting/state/dashboard_layout_providers.dart';

/// Tests must set it to false: an endless periodic rebuild keeps a frame scheduled and
/// `pumpAndSettle` times out.
bool debugDisableDashboardLiveUpdates = false;

/// Why speed data is missing: express mode is a product fact, a missing channel a host fact.
enum SpeedSource {
  available,

  /// Express mode: `ExpressVpnService` never attaches `EngineDataPlane`.
  expressMode,

  /// No `com.haoze.diting/vpn` channel (desktop, gallery, pure Dart tests).
  noNativeChannel,
}

/// Speed series snapshot. [revision] drives incremental redraws in `ui/line_chart.dart`.
class SpeedSeries {
  const SpeedSeries({
    required this.samples,
    required this.revision,
    this.source = SpeedSource.available,
  });

  final List<SpeedSample> samples;
  final int revision;

  /// When unsupported the page explains what is missing instead of drawing zeros.
  final SpeedSource source;

  bool get unsupported => source != SpeedSource.available;

  SpeedSample get last =>
      samples.isEmpty ? const SpeedSample.zero() : samples.last;

  /// Whether any sample was non-zero; an all-zero curve means "no traffic yet".
  bool get hasTraffic => samples.any((sample) => !sample.isZero);

  List<double> upValues() => [for (final s in samples) s.up];

  List<double> downValues() => [for (final s in samples) s.down];
}

final speedSeriesProvider = NotifierProvider<SpeedSeriesNotifier, SpeedSeries>(
  SpeedSeriesNotifier.new,
);

class SpeedSeriesNotifier extends Notifier<SpeedSeries> {
  /// Guards against overlapping polls reordering the samples.
  bool _inFlight = false;

  /// Shared timer and attachment count; two timers halve the window.
  Timer? _timer;
  int _attachments = 0;

  @override
  SpeedSeries build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
      _attachments = 0;
    });
    return const SpeedSeries(samples: [], revision: 0);
  }

  /// Pairs with [detachPolling]; no-op with [debugDisableDashboardLiveUpdates].
  void attachPolling() {
    _attachments++;
    if (debugDisableDashboardLiveUpdates || _timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    // Take one sample immediately so the first point appears at once.
    unawaited(tick());
  }

  void detachPolling() {
    if (_attachments > 0) _attachments--;
    if (_attachments > 0) return;
    _timer?.cancel();
    _timer = null;
  }

  /// Samples the real rate; `unsupported` still appends a zero sample.
  Future<void> tick() async {
    if (_inFlight) return;
    _inFlight = true;
    VpnTrafficRates rates;
    try {
      rates = await _controller().trafficRates();
    } catch (_) {
      rates = const VpnTrafficRates.idle();
    } finally {
      _inFlight = false;
    }
    if (!ref.mounted) return;
    final next = SpeedSample(up: rates.txBps, down: rates.rxBps);
    state = SpeedSeries(
      samples: [...state.samples, next].take(speedSampleCapacity).toList(),
      revision: state.revision + 1,
      source: rates.unsupported
          ? ref.read(workModeProvider) == AppWorkMode.express
                ? SpeedSource.expressMode
                : SpeedSource.noNativeChannel
          : SpeedSource.available,
    );
  }

  /// Clears the curve (mode switch or tunnel restart).
  void clear() {
    state = const SpeedSeries(samples: [], revision: 0);
  }

  VpnController _controller() {
    final express = ref.read(workModeProvider) == AppWorkMode.express;
    return express
        ? ref.read(expressVpnControllerProvider)
        : ref.read(vpnControllerProvider);
  }
}

/// Today's traffic totals, sharing [trafficSnapshotProvider] with `/traffic`; null until ready.
final trafficTotalsProvider = FutureProvider<TrafficTotals?>((ref) async {
  final snapshot = await ref.watch(trafficSnapshotProvider.future);
  return TrafficTotals(
    up: snapshot.txBytes.toDouble(),
    down: snapshot.rxBytes.toDouble(),
  );
});

/// Maps [ServerStatus] and [PowerState] onto the four card levels; server mode adds `stopping`.
final coreStateProvider = Provider<CoreState>((ref) {
  final mode = ref.watch(workModeProvider);
  if (mode == AppWorkMode.server) {
    return switch (ref.watch(serverStatusProvider)) {
      ServerStatus.running => CoreState.running,
      ServerStatus.starting => CoreState.starting,
      ServerStatus.stopping => CoreState.starting,
      ServerStatus.error => CoreState.failed,
      ServerStatus.stopped => CoreState.stopped,
    };
  }
  return switch (ref.watch(powerProvider)) {
    PowerState.running => CoreState.running,
    PowerState.starting || PowerState.stopping => CoreState.starting,
    PowerState.error => CoreState.failed,
    PowerState.stopped => CoreState.stopped,
  };
});
