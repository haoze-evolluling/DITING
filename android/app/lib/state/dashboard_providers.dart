library;

import 'dart:async';

import 'package:diting_android/data/dashboard_models.dart';
import 'package:diting_android/data/vpn/vpn_bridge.dart';
import 'package:diting_android/state/dashboard_layout_providers.dart';
import 'package:diting_android/state/traffic_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_android/ui/scroll_activity.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:diting_android/state/dashboard_layout_providers.dart';

bool debugDisableDashboardLiveUpdates = false;

final visibleDashboardWidgetsProvider = Provider<List<DashboardWidget>>((ref) {
  final widgets = ref.watch(dashboardWidgetsProvider);
  // 网速卡片依赖全隧道流量统计；简洁模式只接管 DNS，不显示它。
  if (ref.watch(workModeProvider).hasTunnelFeatures) return widgets;
  return [
    for (final widget in widgets)
      if (widget != DashboardWidget.networkSpeed) widget,
  ];
});

enum SpeedSource { available, noNativeChannel }

class SpeedSeries {
  const SpeedSeries({
    required this.samples,
    required this.revision,
    this.source = SpeedSource.available,
  });

  final List<SpeedSample> samples;
  final int revision;

  final SpeedSource source;

  bool get unsupported => source != SpeedSource.available;

  SpeedSample get last =>
      samples.isEmpty ? const SpeedSample.zero() : samples.last;

  bool get hasTraffic => samples.any((sample) => !sample.isZero);

  List<double> upValues() => [for (final s in samples) s.up];

  List<double> downValues() => [for (final s in samples) s.down];
}

final speedSeriesProvider = NotifierProvider<SpeedSeriesNotifier, SpeedSeries>(
  SpeedSeriesNotifier.new,
);

class SpeedSeriesNotifier extends Notifier<SpeedSeries> {
  bool _inFlight = false;

  bool _queuedForIdle = false;

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

  void attachPolling() {
    _attachments++;
    if (debugDisableDashboardLiveUpdates || _timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    unawaited(tick());
  }

  void detachPolling() {
    if (_attachments > 0) _attachments--;
    if (_attachments > 0) return;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> tick() async {
    if (ScrollActivityGate.isScrolling) {
      if (!_queuedForIdle) {
        _queuedForIdle = true;
        ScrollActivityGate.whenIdle(() {
          _queuedForIdle = false;
          if (ref.mounted && _attachments > 0) unawaited(tick());
        });
      }
      return;
    }
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
    final source = _speedSourceOf(rates);
    if (source == state.source &&
        state.samples.isNotEmpty &&
        state.samples.last == next) {
      return;
    }
    state = SpeedSeries(
      samples: [...state.samples, next].take(speedSampleCapacity).toList(),
      revision: state.revision + 1,
      source: source,
    );
  }

  void clear() {
    state = const SpeedSeries(samples: [], revision: 0);
  }

  VpnController _controller() {
    final mode = ref.read(workModeProvider);
    if (mode.supportsRootDns && ref.read(rootDnsTakeoverProvider)) {
      return ref.read(rootDnsControllerProvider);
    }
    if (mode == AppWorkMode.express) {
      return ref.read(expressVpnControllerProvider);
    }
    return ref.read(vpnControllerProvider);
  }

  SpeedSource _speedSourceOf(VpnTrafficRates rates) {
    if (!rates.unsupported) return SpeedSource.available;
    return SpeedSource.noNativeChannel;
  }
}

final trafficTotalsProvider = FutureProvider<TrafficTotals?>((ref) async {
  final snapshot = await ref.watch(trafficSnapshotProvider.future);
  return TrafficTotals(
    up: snapshot.txBytes.toDouble(),
    down: snapshot.rxBytes.toDouble(),
  );
});

final coreStateProvider = Provider<CoreState>((ref) {
  return switch (ref.watch(powerProvider)) {
    PowerState.running => CoreState.running,
    PowerState.starting || PowerState.stopping => CoreState.starting,
    PowerState.error => CoreState.failed,
    PowerState.stopped => CoreState.stopped,
  };
});
