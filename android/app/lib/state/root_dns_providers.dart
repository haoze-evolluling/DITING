/// Root-availability probe for the normal-mode takeover setting.
library;

import 'package:diting_android/data/vpn/root_dns_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Auto-disposed so every visit to the settings row performs one fresh `su` probe instead of
/// caching a stale "not available" from before the user granted root.
final rootDnsProbeProvider = FutureProvider.autoDispose<RootDnsProbe>(
  (ref) => probeRootDns(),
);
