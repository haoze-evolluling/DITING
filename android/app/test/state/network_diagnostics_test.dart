import 'dart:io';

import 'package:diting_android/data/db/rust_captive_core.dart';
import 'package:diting_android/data/db/rust_leak_core.dart';
import 'package:diting_android/data/native/diagnostics_bridge.dart';
import 'package:diting_android/state/network_diagnostics_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProbes implements NetworkDiagnosticsProbes {
  _FakeProbes({required this.vpnActive, required this.probe});

  final bool vpnActive;
  final CaptiveHttpProbe probe;

  @override
  Future<NetworkInfoSnapshot> networkInfo() async => NetworkInfoSnapshot(
    interfaceName: 'wlan0',
    localIpv4: '192.168.1.10',
    privateDns: 'off',
    vpnActive: vpnActive,
  );

  @override
  Future<CaptiveHttpProbe> generate204() async => probe;
}

Map<String, Object?> _fakeLeak({
  String? observedExitId,
  String? expectedExitId,
  bool plaintextDnsSeen = false,
  bool? usedConfiguredUpstream,
}) => usedConfiguredUpstream == false
    ? const {'status': 'leak', 'reason': 'bypass_upstream'}
    : const {'status': 'pass', 'reason': 'proxied_without_identity'};

Map<String, Object?> _fakeCaptive({
  int? statusCode,
  String? redirectUrl,
  bool? bodyMatchesExpected,
}) {
  if (statusCode == 204) {
    return const {'state': 'open', 'suspendBlocking': false};
  }
  if (statusCode != null && statusCode >= 300 && statusCode < 400) {
    return {
      'state': 'portal',
      'portalUrl': redirectUrl,
      'suspendBlocking': true,
    };
  }
  return const {'state': 'unknown', 'suspendBlocking': false};
}

ProviderContainer _container({
  required bool vpnActive,
  CaptiveHttpProbe probe = const CaptiveHttpProbe(statusCode: 204),
}) {
  final container = ProviderContainer(
    overrides: [
      networkDiagnosticsProbesProvider.overrideWithValue(
        _FakeProbes(vpnActive: vpnActive, probe: probe),
      ),
      leakEvaluatorProvider.overrideWithValue(_fakeLeak),
      captiveEvaluatorProvider.overrideWithValue(_fakeCaptive),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('network diagnostics state', () {
    test('leak check reports a bypass when the tunnel is down', () async {
      final container = _container(vpnActive: false);
      await container.read(networkDiagnosticsProvider.notifier).runLeakCheck();
      final state = container.read(networkDiagnosticsProvider);
      expect(state.leak?.status, 'leak');
      expect(state.leak?.reason, 'bypass_upstream');
      expect(state.vpnActive, isFalse);
    });

    test('leak check passes when the tunnel is up', () async {
      final container = _container(vpnActive: true);
      await container.read(networkDiagnosticsProvider.notifier).runLeakCheck();
      expect(container.read(networkDiagnosticsProvider).leak?.status, 'pass');
    });

    test('captive check surfaces a portal url', () async {
      final container = _container(
        vpnActive: true,
        probe: const CaptiveHttpProbe(
          statusCode: 302,
          redirectUrl: 'http://wifi.portal/login',
        ),
      );
      await container
          .read(networkDiagnosticsProvider.notifier)
          .runCaptiveCheck();
      final captive = container.read(networkDiagnosticsProvider).captive;
      expect(captive?.state, 'portal');
      expect(captive?.portalUrl, 'http://wifi.portal/login');
      expect(captive?.suspendBlocking, isTrue);
    });
  });

  group('rust kernels over dart:ffi', () {
    // The host build produces `rust/target/debug/diting_*_core.dll`; skip elsewhere.
    test('leak core round-trips a leak verdict', () {
      if (!Platform.isWindows) return;
      final verdict = RustLeakCore.instance.evaluate(
        plaintextDnsSeen: true,
      );
      expect(verdict['status'], 'leak');
      expect(verdict['reason'], 'plaintext_dns_egress');
    });

    test('captive core round-trips an open verdict', () {
      if (!Platform.isWindows) return;
      final verdict = RustCaptiveCore.instance.evaluate(
        statusCode: 204,
        bodyMatchesExpected: true,
      );
      expect(verdict['state'], 'open');
      expect(verdict['suspendBlocking'], isFalse);
    });
  });
}
