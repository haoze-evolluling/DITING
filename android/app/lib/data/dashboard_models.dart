library;

import 'package:diting_shared/app/l10n/l10n.dart';


class SpeedSample {
  const SpeedSample({required this.up, required this.down});

  const SpeedSample.zero() : up = 0, down = 0;

  final double up;
  final double down;

  bool get isZero => up == 0 && down == 0;

  @override
  bool operator ==(Object other) =>
      other is SpeedSample && other.up == up && other.down == down;

  @override
  int get hashCode => Object.hash(up, down);
}

const speedSampleCapacity = 60;

class TrafficTotals {
  const TrafficTotals({required this.up, required this.down});

  const TrafficTotals.zero() : up = 0, down = 0;

  final double up;
  final double down;

  double get total => up + down;
}

enum CoreState {
  running,
  stopped,
  starting,
  failed;

  String label(AppL10n l10n) => switch (this) {
    CoreState.running => l10n.stateRunning,
    CoreState.stopped => l10n.stateStopped,
    CoreState.starting => l10n.stateStarting,
    CoreState.failed => l10n.powerStateError,
  };

  bool get isRunning => this == CoreState.running;
}

enum DashboardWidget {
  provider,

  resolution,
  status,
  networkSpeed,
  siteLatency,
  memoryInfo,
  intranetIp;

  String label(AppL10n l10n) => switch (this) {
    DashboardWidget.provider => l10n.homeProviderSingleLabel,
    DashboardWidget.resolution => l10n.resolutionModeTitle,
    DashboardWidget.status => l10n.statusTitle,
    DashboardWidget.networkSpeed => l10n.speedTitle,
    DashboardWidget.siteLatency => l10n.siteLatencyTitle,
    DashboardWidget.memoryInfo => l10n.memoryTitle,
    DashboardWidget.intranetIp => l10n.intranetIpTitle,
  };
}

const defaultDashboardWidgets = <DashboardWidget>[
  DashboardWidget.provider,
  DashboardWidget.resolution,
  DashboardWidget.status,
  DashboardWidget.networkSpeed,
  DashboardWidget.siteLatency,
  DashboardWidget.memoryInfo,
  DashboardWidget.intranetIp,
];
