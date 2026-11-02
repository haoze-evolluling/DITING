import 'package:diting_android/data/server/dns_server_bridge.dart';

/// Deterministic stand-in for the standalone DNS server channel.
class FakeDnsServerController implements DnsServerController {
  FakeDnsServerController({
    this.started = true,
    this.error,
    this.delay = Duration.zero,
    this.statusValue = const DnsServerStatus(
      running: false,
      persisted: false,
      port: 1053,
    ),
  });

  final bool started;
  final String? error;
  final Duration delay;
  DnsServerStatus statusValue;

  int startCalls = 0;
  int stopCalls = 0;
  DnsServerStartRequest? lastRequest;

  @override
  Future<DnsServerStartResult> start(DnsServerStartRequest request) async {
    startCalls++;
    lastRequest = request;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return DnsServerStartResult(
      started: started,
      error: started ? null : error,
    );
  }

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<DnsServerStatus> status() async => statusValue;
}
