/// Tunnel power state. Lives outside `state/work_mode_providers.dart` so the header widgets that
/// render it can be shared with the desktop build, which has no VPN channel.
library;

import 'package:diting/app/l10n/l10n.dart';

enum PowerState {
  stopped,
  starting,
  running,
  stopping,
  error;

  String label(AppL10n l10n) => switch (this) {
    PowerState.stopped => l10n.stateStopped,
    PowerState.starting => l10n.stateStarting,
    PowerState.running => l10n.stateRunning,
    PowerState.stopping => l10n.stateStopping,
    PowerState.error => l10n.powerStateError,
  };

  bool get isBusy => this == starting || this == stopping;

  bool get isRunning => this == running;
}
