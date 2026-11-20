library;

import 'package:diting_android/data/vpn/root_dns_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final rootDnsProbeProvider = FutureProvider.autoDispose<RootDnsProbe>(
  (ref) => probeRootDns(),
);
