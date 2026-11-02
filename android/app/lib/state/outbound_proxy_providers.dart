/// Outbound-proxy state: keys stay in `dns_vpn_prefs`, credentials are encrypted, so go through
/// [OutboundProxyStore].
library;

import 'package:diting_android/data/native/outbound_proxy_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in `main()`; the in-memory default keeps tests and non-Android hosts working.
final outboundProxyStoreProvider = Provider<OutboundProxyStore>(
  (ref) => MemoryOutboundProxyStore(),
);

/// Reloaded after every save; [bump] is called by the settings page because a tunnel start reads
/// it.
class OutboundProxyRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final outboundProxyRevisionProvider =
    NotifierProvider<OutboundProxyRevision, int>(OutboundProxyRevision.new);

final outboundProxyConfigProvider = FutureProvider<OutboundProxyConfig>((ref) {
  ref.watch(outboundProxyRevisionProvider);
  return ref.watch(outboundProxyStoreProvider).read();
});
