/// Runtime dependencies and settings of the network tools; probes go through the native
/// `DiagnosticsRunner`.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/diagnostics_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `NetworkToolsSettingsStore.PREFS_NAME`
const networkToolsContainer = 'network_tools_settings';

/// Per-tool "resolve via tunnel" keys, copied verbatim from the Kotlin constants.
const pingViaTunnelKey = 'ping_via_tunnel';
const dnsLookupViaTunnelKey = 'dns_lookup_via_tunnel';
const tracerouteViaTunnelKey = 'traceroute_via_tunnel';

/// Native runner; `main.dart` overrides it with `GuardedDiagnosticsRunner`, the default reports
/// failures.
final diagnosticsRunnerProvider = Provider<DiagnosticsRunner>(
  (ref) => const GuardedDiagnosticsRunner(UnavailableDiagnosticsRunner()),
);

/// Turns platform exceptions into `success=false` results: the panel resets busy after the await.
class GuardedDiagnosticsRunner implements DiagnosticsRunner {
  const GuardedDiagnosticsRunner(this._inner);

  final DiagnosticsRunner _inner;

  @override
  Future<PingSummary> ping(
    String target, {
    int count = 4,
    int timeoutSeconds = 3,
  }) => _guard(
    () => _inner.ping(target, count: count, timeoutSeconds: timeoutSeconds),
    (message) => PingSummary(
      target: target,
      transmitted: 0,
      received: 0,
      lossPercent: 100,
      success: false,
      message: message,
    ),
  );

  @override
  Future<TraceResult> traceRoute(String target, {int maxHops = 30}) => _guard(
    () => _inner.traceRoute(target, maxHops: maxHops),
    (message) => TraceResult(
      target: target,
      hops: const [],
      success: false,
      message: message,
    ),
  );

  @override
  Future<DnsLookupResult> lookupDns(
    String domain, {
    bool viaTunnel = false,
    bool ipv4 = true,
    String? server,
  }) => _guard(
    () => _inner.lookupDns(
      domain,
      viaTunnel: viaTunnel,
      ipv4: ipv4,
      server: server,
    ),
    (message) => DnsLookupResult(
      domain: domain,
      source: 'error',
      answers: const [],
      elapsedMs: 0,
      error: message,
    ),
  );

  @override
  Future<NetworkInfoSnapshot> networkInfo() => _guard(
    () => _inner.networkInfo(),
    (message) => NetworkInfoSnapshot(
      interfaceName: '',
      localIpv4: '',
      privateDns: 'off',
      vpnActive: false,
      gateway: message,
    ),
  );

  static Future<T> _guard<T>(
    Future<T> Function() run,
    T Function(String message) onError,
  ) async {
    try {
      return await run();
    } on MissingPluginException {
      return onError(currentL10n.diagnosticsChannelUnavailable);
    } on PlatformException catch (error) {
      return onError(_platformErrorText(error));
    } on UnsupportedError {
      return onError(currentL10n.diagnosticsUnsupported);
    }
  }

  static String _platformErrorText(PlatformException error) {
    final detail = error.message;
    return detail == null || detail.isEmpty
        ? currentL10n.diagnosticsFailedCode(error.code)
        : currentL10n.diagnosticsFailed(detail);
  }
}

/// Default for hosts without the channel (desktop, unit tests): readable failures, never throws.
class UnavailableDiagnosticsRunner implements DiagnosticsRunner {
  const UnavailableDiagnosticsRunner();

  @override
  Future<PingSummary> ping(
    String target, {
    int count = 4,
    int timeoutSeconds = 3,
  }) async => PingSummary(
    target: target,
    transmitted: 0,
    received: 0,
    lossPercent: 100,
    success: false,
    message: currentL10n.diagnosticsPingUnsupported,
  );

  @override
  Future<TraceResult> traceRoute(String target, {int maxHops = 30}) async =>
      TraceResult(
        target: target,
        hops: const [],
        success: false,
        message: currentL10n.diagnosticsTraceUnsupported,
      );

  @override
  Future<DnsLookupResult> lookupDns(
    String domain, {
    bool viaTunnel = false,
    bool ipv4 = true,
    String? server,
  }) async => DnsLookupResult(
    domain: domain,
    source: 'error',
    answers: const [],
    elapsedMs: 0,
    error: currentL10n.diagnosticsDnsUnsupported,
  );

  @override
  Future<NetworkInfoSnapshot> networkInfo() async => const NetworkInfoSnapshot(
    interfaceName: '',
    localIpv4: '',
    privateDns: 'off',
    vpnActive: false,
  );
}

/// Physical network snapshot read by the header bar; no mock constants.
final networkInfoProvider = FutureProvider<NetworkInfoSnapshot>(
  (ref) => ref.watch(diagnosticsRunnerProvider).networkInfo(),
);

class NetworkToolFlags {
  const NetworkToolFlags({
    this.pingViaTunnel = false,
    this.dnsLookupViaTunnel = false,
    this.tracerouteViaTunnel = false,
  });

  final bool pingViaTunnel;
  final bool dnsLookupViaTunnel;
  final bool tracerouteViaTunnel;

  NetworkToolFlags copyWith({
    bool? pingViaTunnel,
    bool? dnsLookupViaTunnel,
    bool? tracerouteViaTunnel,
  }) => NetworkToolFlags(
    pingViaTunnel: pingViaTunnel ?? this.pingViaTunnel,
    dnsLookupViaTunnel: dnsLookupViaTunnel ?? this.dnsLookupViaTunnel,
    tracerouteViaTunnel: tracerouteViaTunnel ?? this.tracerouteViaTunnel,
  );
}

/// Reads `network_tools_settings`, defaulting false; watches the revision since prefs are
/// unobservable.
final networkToolFlagsProvider = Provider<NetworkToolFlags>((ref) {
  ref.watch(legacySettingsRevisionProvider);
  final store = ref.watch(legacyPrefsStoreProvider);
  bool read(String key) => store.read(networkToolsContainer, key) == true;
  return NetworkToolFlags(
    pingViaTunnel: read(pingViaTunnelKey),
    dnsLookupViaTunnel: read(dnsLookupViaTunnelKey),
    tracerouteViaTunnel: read(tracerouteViaTunnelKey),
  );
});

/// Writes one switch and invalidates every reader of `network_tools_settings`.
void setNetworkToolFlag(WidgetRef ref, String key, bool value) {
  ref.read(legacyPrefsStoreProvider).putBool(networkToolsContainer, key, value);
  ref.read(legacySettingsRevisionProvider.notifier).bump();
}

/// Strips scheme, path, user info and port; `2001:db8::1` survives, only a `:` plus digits is a
/// port.
String sanitizeProbeHost(String input) {
  var value = input.trim();
  if (value.isEmpty) {
    return value;
  }
  final schemeIndex = value.indexOf('://');
  if (schemeIndex >= 0) {
    value = value.substring(schemeIndex + 3);
  }
  final cutIndex = _firstIndexOfAny(value, const ['/', '?', '#']);
  if (cutIndex >= 0) {
    value = value.substring(0, cutIndex);
  }
  final atIndex = value.lastIndexOf('@');
  if (atIndex >= 0) {
    value = value.substring(atIndex + 1);
  }
  if (value.startsWith('[')) {
    final endIndex = value.indexOf(']');
    return endIndex > 0 ? value.substring(1, endIndex) : value;
  }
  if (!value.contains('::') && ':'.allMatches(value).length == 1) {
    final afterColon = value.substring(value.indexOf(':') + 1);
    if (afterColon.isNotEmpty && int.tryParse(afterColon) != null) {
      value = value.substring(0, value.indexOf(':'));
    }
  }
  return value;
}

int _firstIndexOfAny(String value, List<String> needles) {
  var best = -1;
  for (final needle in needles) {
    final index = value.indexOf(needle);
    if (index >= 0 && (best < 0 || index < best)) {
      best = index;
    }
  }
  return best;
}

/// Sanitises and validates the target; a non-null error is shown instead of probing.
({String host, String? error}) resolveProbeHost(String input) {
  final host = sanitizeProbeHost(input);
  if (host.isEmpty) {
    return (host: host, error: currentL10n.diagnosticsEmptyTarget);
  }
  if (host.contains(' ')) {
    return (host: host, error: currentL10n.diagnosticsTargetHasSpace);
  }
  return (host: host, error: null);
}

String dnsSourceLabel(String source) => switch (source) {
  'upstream' => currentL10n.diagnosticsAnswerUpstream,
  'cache' => currentL10n.diagnosticsAnswerCache,
  'rewrite' => currentL10n.diagnosticsAnswerRewrite,
  'blocked' => currentL10n.diagnosticsAnswerBlocked,
  _ => currentL10n.diagnosticsAnswerFailed,
};

/// An empty interface name means there is no active network.
String networkInterfaceLabel(NetworkInfoSnapshot snapshot) =>
    snapshot.interfaceName.isEmpty ? currentL10n.diagnosticsNoActiveNetwork : snapshot.interfaceName;

/// Formats a latency value; null is rendered as a dash by the caller.
String latencyText(double? value) =>
    value == null ? '—' : '${value.toStringAsFixed(1)} ms';
