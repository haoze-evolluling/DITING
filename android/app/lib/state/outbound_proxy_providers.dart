library;

import 'package:diting_android/data/native/outbound_proxy_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final outboundProxyStoreProvider = Provider<OutboundProxyStore>(
  (ref) => MemoryOutboundProxyStore(),
);

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
