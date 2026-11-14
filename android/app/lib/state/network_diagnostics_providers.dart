/// State for the N6 network-diagnostics page: a DNS-leak check and a Captive Portal check.
///
/// The probes are I/O and live behind [NetworkDiagnosticsProbes] so a widget test can inject fakes;
/// the *verdicts* come from the Rust kernels (`diting-leak-core` / `diting-captive-core`) through
/// [LeakEvaluator] / [CaptiveEvaluator], which one implementation the page shares.
library;

import 'dart:io';

import 'package:diting_android/data/db/rust_captive_core.dart';
import 'package:diting_android/data/db/rust_leak_core.dart';
import 'package:diting_android/data/native/diagnostics_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One `generate_204` result, normalized for the captive kernel.
class CaptiveHttpProbe {
  const CaptiveHttpProbe({
    this.statusCode,
    this.redirectUrl,
    this.bodyMatchesExpected,
  });

  final int? statusCode;
  final String? redirectUrl;
  final bool? bodyMatchesExpected;
}

/// The platform probes. A fake in tests; the real one uses the method channel + `HttpClient`.
abstract class NetworkDiagnosticsProbes {
  Future<NetworkInfoSnapshot> networkInfo();

  Future<CaptiveHttpProbe> generate204();
}

/// Default implementation: `networkInfo` over the diagnostics channel, `generate_204` over
/// `HttpClient` (redirects disabled so the portal's 3xx is visible).
class MethodChannelDiagnosticsProbes implements NetworkDiagnosticsProbes {
  MethodChannelDiagnosticsProbes({DiagnosticsRunner? runner})
    : _runner = runner ?? MethodChannelDiagnosticsRunner();

  final DiagnosticsRunner _runner;

  static final _probeUrl = Uri.parse(
    'http://connectivitycheck.gstatic.com/generate_204',
  );

  @override
  Future<NetworkInfoSnapshot> networkInfo() => _runner.networkInfo();

  @override
  Future<CaptiveHttpProbe> generate204() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..idleTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .getUrl(_probeUrl)
          .timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final location = response.headers.value(HttpHeaders.locationHeader);
      final redirectUrl = response.isRedirect ? location : null;
      await response.drain<void>();
      return CaptiveHttpProbe(
        statusCode: response.statusCode,
        redirectUrl: redirectUrl,
        // A 204 means the body is the expected empty body; other codes are judged by status.
        bodyMatchesExpected: response.statusCode == 204 ? true : null,
      );
    } finally {
      client.close(force: true);
    }
  }
}

typedef LeakEvaluator =
    Map<String, Object?> Function({
      String? observedExitId,
      String? expectedExitId,
      bool plaintextDnsSeen,
      bool? usedConfiguredUpstream,
    });

typedef CaptiveEvaluator =
    Map<String, Object?> Function({
      int? statusCode,
      String? redirectUrl,
      bool? bodyMatchesExpected,
    });

final networkDiagnosticsProbesProvider = Provider<NetworkDiagnosticsProbes>(
  (ref) => MethodChannelDiagnosticsProbes(),
);

final leakEvaluatorProvider = Provider<LeakEvaluator>(
  (ref) => ({
    String? observedExitId,
    String? expectedExitId,
    bool plaintextDnsSeen = false,
    bool? usedConfiguredUpstream,
  }) => RustLeakCore.instance.evaluate(
    observedExitId: observedExitId,
    expectedExitId: expectedExitId,
    plaintextDnsSeen: plaintextDnsSeen,
    usedConfiguredUpstream: usedConfiguredUpstream,
  ),
);

final captiveEvaluatorProvider = Provider<CaptiveEvaluator>(
  (ref) => ({
    int? statusCode,
    String? redirectUrl,
    bool? bodyMatchesExpected,
  }) => RustCaptiveCore.instance.evaluate(
    statusCode: statusCode,
    redirectUrl: redirectUrl,
    bodyMatchesExpected: bodyMatchesExpected,
  ),
);

/// The three-state leak result plus its reason code.
class DiagnosticsResult {
  const DiagnosticsResult({required this.status, required this.reason});

  /// `pass` / `leak` / `unknown`.
  final String status;

  /// Stable reason code, localized by the page.
  final String reason;

  factory DiagnosticsResult.fromMap(Map<String, Object?> map) =>
      DiagnosticsResult(
        status: map['status'] as String? ?? 'unknown',
        reason: map['reason'] as String? ?? 'insufficient_data',
      );
}

/// The captive verdict.
class CaptiveResult {
  const CaptiveResult({
    required this.state,
    this.portalUrl,
    required this.suspendBlocking,
  });

  /// `open` / `portal` / `unknown`.
  final String state;
  final String? portalUrl;
  final bool suspendBlocking;

  factory CaptiveResult.fromMap(Map<String, Object?> map) => CaptiveResult(
    state: map['state'] as String? ?? 'unknown',
    portalUrl: map['portalUrl'] as String?,
    suspendBlocking: map['suspendBlocking'] == true,
  );
}

class NetworkDiagnosticsState {
  const NetworkDiagnosticsState({
    this.leakBusy = false,
    this.captiveBusy = false,
    this.leak,
    this.captive,
    this.vpnActive,
    this.error,
  });

  final bool leakBusy;
  final bool captiveBusy;
  final DiagnosticsResult? leak;
  final CaptiveResult? captive;
  final bool? vpnActive;
  final String? error;

  NetworkDiagnosticsState copyWith({
    bool? leakBusy,
    bool? captiveBusy,
    DiagnosticsResult? leak,
    CaptiveResult? captive,
    bool? vpnActive,
    String? error,
    bool clearError = false,
  }) => NetworkDiagnosticsState(
    leakBusy: leakBusy ?? this.leakBusy,
    captiveBusy: captiveBusy ?? this.captiveBusy,
    leak: leak ?? this.leak,
    captive: captive ?? this.captive,
    vpnActive: vpnActive ?? this.vpnActive,
    error: clearError ? null : (error ?? this.error),
  );
}

class NetworkDiagnosticsNotifier extends Notifier<NetworkDiagnosticsState> {
  @override
  NetworkDiagnosticsState build() => const NetworkDiagnosticsState();

  /// DNS leak: the probe is whether the tunnel is carrying queries at all. When it is not, the
  /// verdict is a definite leak ("bypass_upstream"); when it is, there is no expected identity to
  /// compare against, so the kernel reports a proxied pass.
  Future<void> runLeakCheck() async {
    if (state.leakBusy) return;
    state = state.copyWith(leakBusy: true, clearError: true);
    try {
      final info = await ref.read(networkDiagnosticsProbesProvider).networkInfo();
      final verdict = ref.read(leakEvaluatorProvider)(
        plaintextDnsSeen: false,
        usedConfiguredUpstream: info.vpnActive,
      );
      state = state.copyWith(
        leakBusy: false,
        leak: DiagnosticsResult.fromMap(verdict),
        vpnActive: info.vpnActive,
      );
    } catch (_) {
      state = state.copyWith(leakBusy: false, error: 'failed');
    }
  }

  /// Captive portal: run the `generate_204` probe and let the kernel judge it.
  Future<void> runCaptiveCheck() async {
    if (state.captiveBusy) return;
    state = state.copyWith(captiveBusy: true, clearError: true);
    try {
      final probe = await ref
          .read(networkDiagnosticsProbesProvider)
          .generate204();
      final verdict = ref.read(captiveEvaluatorProvider)(
        statusCode: probe.statusCode,
        redirectUrl: probe.redirectUrl,
        bodyMatchesExpected: probe.bodyMatchesExpected,
      );
      state = state.copyWith(
        captiveBusy: false,
        captive: CaptiveResult.fromMap(verdict),
      );
    } catch (_) {
      state = state.copyWith(captiveBusy: false, error: 'failed');
    }
  }
}

final networkDiagnosticsProvider =
    NotifierProvider<NetworkDiagnosticsNotifier, NetworkDiagnosticsState>(
      NetworkDiagnosticsNotifier.new,
    );
