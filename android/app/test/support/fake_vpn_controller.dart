import 'package:diting_android/data/vpn/vpn_bridge.dart';

class FakeVpnController implements VpnController {
  FakeVpnController({
    this.prepared = true,
    this.started = true,
    this.error,
    this.delay = Duration.zero,
  });

  final bool prepared;
  final bool started;
  final String? error;

  final Duration delay;

  int startCalls = 0;
  int stopCalls = 0;
  VpnStartRequest? lastRequest;
  VpnStatus statusValue = const VpnStatus(running: false, persisted: false);

  VpnTrafficRates ratesValue = const VpnTrafficRates.idle();
  int trafficRatesCalls = 0;

  @override
  void Function(bool granted)? onPrepareResult;

  @override
  Future<bool> prepare() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return prepared;
  }

  void grantPermission() => onPrepareResult?.call(true);

  @override
  Future<VpnStartResult> start(VpnStartRequest request) async {
    startCalls++;
    lastRequest = request;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return VpnStartResult(
      started: started,
      needsPermission: false,
      error: started ? null : error,
    );
  }

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<VpnStatus> status() async => statusValue;

  @override
  Future<VpnTrafficRates> trafficRates() async {
    trafficRatesCalls++;
    return ratesValue;
  }

  int applyDnsConfigCalls = 0;
  String? lastAppliedDnsConfig;

  @override
  Future<String?> applyDnsConfig(String dnsConfig) async {
    applyDnsConfigCalls++;
    lastAppliedDnsConfig = dnsConfig;
    return null;
  }
}
