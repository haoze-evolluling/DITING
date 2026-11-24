import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/ipv6_mode.dart';

String ipv6ModeLabel(AppL10n l10n, Ipv6Mode mode) => switch (mode) {
  Ipv6Mode.ipv4 => l10n.ipv6ModeIpv4,
  Ipv6Mode.auto => l10n.ipv6ModeAuto,
  Ipv6Mode.ipv6 => l10n.ipv6ModeIpv6,
};
