/// Dart side of `com.haoze.diting/outbound_proxy`. Credentials sit in `dns_vpn_prefs` under an
/// AndroidKeyStore key Dart cannot reach, so the proxy is composed natively. The app package is
/// part of the config: Android lets only one app bind a loopback port.
///
/// Validation, target filtering and the engine JSON come from
/// `rust/diting-outbound-proxy-core`, which imports the engine's own protocol/host/port/credential/
/// scope rules; only the localized sentences and the channel stay here.
library;

import 'package:diting_android/data/db/rust_outbound_proxy_core.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:flutter/services.dart';

/// Matches 1.4.3 `OutboundProxyProtocol`; `storageValue` is parsed by the Go engine.
enum OutboundProxyProtocol {
  socks5('socks5', 'SOCKS5'),
  http('http', 'HTTP CONNECT');

  const OutboundProxyProtocol(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static OutboundProxyProtocol fromStorageValue(String? value) =>
      values.firstWhere(
        (item) => item.storageValue == value,
        orElse: () => OutboundProxyProtocol.socks5,
      );
}

/// Which apps the proxy applies to. `all` is the original whole-device behaviour; `apps` proxies only
/// [OutboundProxyConfig.targetPackages] and keeps DNS upstream queries and every other app direct.
enum OutboundProxyScope {
  all('all'),
  apps('apps');

  const OutboundProxyScope(this.storageValue);

  final String storageValue;

  static OutboundProxyScope fromStorageValue(String? value) =>
      value == apps.storageValue ? apps : all;
}

class OutboundProxyConfig {
  const OutboundProxyConfig({
    this.enabled = false,
    this.protocol = OutboundProxyProtocol.socks5,
    this.host = '127.0.0.1',
    this.port = 7890,
    this.username = '',
    this.password = '',
    this.proxyAppPackage = '',
    this.scope = OutboundProxyScope.all,
    this.targetPackages = const {},
    this.status = 'disabled',
    this.statusMessage = '',
  });

  final bool enabled;
  final OutboundProxyProtocol protocol;
  final String host;
  final int port;
  final String username;
  final String password;

  final String proxyAppPackage;

  final OutboundProxyScope scope;

  /// Apps routed through the proxy when [scope] is [OutboundProxyScope.apps].
  final Set<String> targetPackages;

  /// Engine-reported state: `disabled`, `connecting`, `ready` or `error`.
  final String status;
  final String statusMessage;

  OutboundProxyConfig copyWith({
    bool? enabled,
    OutboundProxyProtocol? protocol,
    String? host,
    int? port,
    String? username,
    String? password,
    String? proxyAppPackage,
    OutboundProxyScope? scope,
    Set<String>? targetPackages,
    String? status,
    String? statusMessage,
  }) => OutboundProxyConfig(
    enabled: enabled ?? this.enabled,
    protocol: protocol ?? this.protocol,
    host: host ?? this.host,
    port: port ?? this.port,
    username: username ?? this.username,
    password: password ?? this.password,
    proxyAppPackage: proxyAppPackage ?? this.proxyAppPackage,
    scope: scope ?? this.scope,
    targetPackages: targetPackages ?? this.targetPackages,
    status: status ?? this.status,
    statusMessage: statusMessage ?? this.statusMessage,
  );

  /// The Dart enum spellings crossed into the native map; status fields stay out of the rules.
  Map<String, Object?> _coreConfig() => {
    'enabled': enabled,
    'protocol': protocol.storageValue,
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'proxyAppPackage': proxyAppPackage,
    'scope': scope.storageValue,
    'targetPackages': targetPackages.toList(),
  };

  /// Mirrors `Engine` and the settings page order, so the first offending field is reported
  /// identically; a null [installedPackages] skips the "not installed" check rather than failing
  /// closed. The sentences stay here; the rule and its token come from the kernel.
  String? validationError({
    String? selfPackage,
    Set<String>? installedPackages,
  }) {
    final code = RustOutboundProxyCore.instance.validationError(
      _coreConfig(),
      selfPackage: selfPackage,
      installedPackages: installedPackages?.toList(),
    );
    return switch (code) {
      'host' => currentL10n.outboundProxyHostInvalid,
      'port' => currentL10n.outboundProxyPortRange,
      'proxyAppRequired' => currentL10n.outboundProxyAppRequired,
      'proxyAppSelf' => currentL10n.outboundProxySelfNotAllowed,
      'proxyAppMissing' => currentL10n.outboundProxyAppMissing,
      'credentials' => currentL10n.outboundProxyCredentialsTooLong,
      'targets' => currentL10n.outboundProxyTargetsRequired,
      _ => null,
    };
  }

  /// Targets without the proxy app: it sits outside the TUN, so selecting it would have no effect.
  Set<String> get effectiveTargets => {
    ...RustOutboundProxyCore.instance.effectiveTargets(_coreConfig()),
  };

  /// JSON handed to `Engine.configureOutboundProxy`. `port` must be a JSON number: Go unmarshals
  /// into `Port int` (`tunnel/flow_outbound.go:29`), and a string leaves the proxy silently
  /// disabled. Per-app scope adds `scope` and `packages`; the VPN service turns `packages` into
  /// the `uids` the engine matches on.
  String toEngineJson() =>
      RustOutboundProxyCore.instance.engineJson(_coreConfig());

  static OutboundProxyConfig fromMap(Map<Object?, Object?> map) =>
      OutboundProxyConfig(
        enabled: map['enabled'] == true,
        protocol: OutboundProxyProtocol.fromStorageValue(
          map['protocol'] as String?,
        ),
        host: map['host'] as String? ?? '127.0.0.1',
        port: (map['port'] as num?)?.toInt() ?? 7890,
        username: map['username'] as String? ?? '',
        password: map['password'] as String? ?? '',
        proxyAppPackage: map['proxyAppPackage'] as String? ?? '',
        scope: OutboundProxyScope.fromStorageValue(map['scope'] as String?),
        targetPackages: {
          for (final item in (map['targetPackages'] as List?) ?? const [])
            if (item is String && item.isNotEmpty) item,
        },
        status: map['status'] as String? ?? 'disabled',
        statusMessage: map['statusMessage'] as String? ?? '',
      );
}

abstract class OutboundProxyStore {
  Future<OutboundProxyConfig> read();

  Future<void> write(OutboundProxyConfig config);

  Future<void> reset();

  /// Engine-reported status, persisted so the page can show it after a restart.
  Future<void> setStatus(String state, String message);
}

class MethodChannelOutboundProxyStore implements OutboundProxyStore {
  MethodChannelOutboundProxyStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'com.haoze.diting/outbound_proxy';

  final MethodChannel _channel;

  @override
  Future<OutboundProxyConfig> read() async {
    final raw = await _channel.invokeMethod<Object?>('read');
    return OutboundProxyConfig.fromMap(
      raw is Map ? Map<Object?, Object?>.from(raw) : const {},
    );
  }

  @override
  Future<void> write(OutboundProxyConfig config) =>
      _channel.invokeMethod<void>('write', {
        'enabled': config.enabled,
        'protocol': config.protocol.storageValue,
        'host': config.host,
        'port': config.port,
        'username': config.username,
        'password': config.password,
        'proxyAppPackage': config.proxyAppPackage,
        'scope': config.scope.storageValue,
        'targetPackages': config.targetPackages.toList(),
      });

  @override
  Future<void> reset() => _channel.invokeMethod<void>('reset');

  @override
  Future<void> setStatus(String state, String message) => _channel
      .invokeMethod<void>('setStatus', {'state': state, 'message': message});
}

class MemoryOutboundProxyStore implements OutboundProxyStore {
  OutboundProxyConfig _config = const OutboundProxyConfig();

  @override
  Future<OutboundProxyConfig> read() async => _config;

  @override
  Future<void> write(OutboundProxyConfig config) async => _config = config;

  @override
  Future<void> reset() async => _config = const OutboundProxyConfig();

  @override
  Future<void> setStatus(String state, String message) async =>
      _config = _config.copyWith(status: state, statusMessage: message);
}
