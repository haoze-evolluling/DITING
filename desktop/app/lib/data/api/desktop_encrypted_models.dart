/// The encrypted DNS server: its listeners, certificate and discovery config.
///
/// `GET /api/v1/encrypted/dns/status` carries the config, a certificate summary without private key
/// material, the addresses that are actually listening and the URLs a client can be given. A
/// configured port is not a bound port, so the page always shows both.
library;

bool _bool(Object? value) => value == true;

int _int(Object? value) => switch (value) {
  num() => value.toInt(),
  String() => int.tryParse(value) ?? 0,
  _ => 0,
};

List<String> _strings(Object? value) => switch (value) {
  List() => [for (final item in value) '$item'],
  _ => const [],
};

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

class DesktopEncryptedConfig {
  const DesktopEncryptedConfig({
    required this.enabled,
    required this.dotEnabled,
    required this.dohEnabled,
    required this.doqEnabled,
    required this.ddrEnabled,
    required this.listenAddress,
    required this.dotPort,
    required this.dohPort,
    required this.doqPort,
    required this.dohPath,
    required this.serverName,
    required this.certKeyType,
    required this.certCommonName,
    required this.certDnsNames,
    required this.certIpAddresses,
    required this.certValidDays,
    required this.proxyEnabled,
    required this.proxyTrustedSources,
    required this.proxyClientIpHeader,
  });

  factory DesktopEncryptedConfig.fromJson(Map<String, Object?> json) {
    final cert = _map(json['cert']);
    final proxy = _map(json['reverseProxy']);
    return DesktopEncryptedConfig(
      enabled: _bool(json['enabled']),
      dotEnabled: _bool(json['dotEnabled']),
      dohEnabled: _bool(json['dohEnabled']),
      doqEnabled: _bool(json['doqEnabled']),
      ddrEnabled: _bool(json['ddrEnabled']),
      listenAddress: '${json['listenAddress'] ?? ''}',
      dotPort: _int(json['dotPort']),
      dohPort: _int(json['dohPort']),
      doqPort: _int(json['doqPort']),
      dohPath: '${json['dohPath'] ?? ''}',
      serverName: '${json['serverName'] ?? ''}',
      certKeyType: '${cert['keyType'] ?? ''}',
      certCommonName: '${cert['commonName'] ?? ''}',
      certDnsNames: _strings(cert['dnsNames']),
      certIpAddresses: _strings(cert['ipAddresses']),
      certValidDays: _int(cert['validDays']),
      proxyEnabled: _bool(proxy['enabled']),
      proxyTrustedSources: _strings(proxy['trustedSources']),
      proxyClientIpHeader: '${proxy['clientIpHeader'] ?? ''}',
    );
  }

  final bool enabled;
  final bool dotEnabled;
  final bool dohEnabled;
  final bool doqEnabled;
  final bool ddrEnabled;
  final String listenAddress;
  final int dotPort;
  final int dohPort;
  final int doqPort;
  final String dohPath;
  final String serverName;

  final String certKeyType;
  final String certCommonName;
  final List<String> certDnsNames;
  final List<String> certIpAddresses;
  final int certValidDays;

  final bool proxyEnabled;
  final List<String> proxyTrustedSources;
  final String proxyClientIpHeader;

  bool get anyProtocol => dotEnabled || dohEnabled || doqEnabled;

  int get effectiveDotPort => dotPort > 0 ? dotPort : 853;
  int get effectiveDohPort => dohPort > 0 ? dohPort : 443;
  int get effectiveDoqPort => doqPort > 0 ? doqPort : 853;
  String get effectiveDohPath => dohPath.isEmpty ? '/dns-query' : dohPath;
}

class DesktopCertInfo {
  const DesktopCertInfo({
    required this.source,
    required this.subject,
    required this.issuer,
    required this.notAfter,
    required this.dnsNames,
    required this.ipAddresses,
    required this.daysRemaining,
    required this.fingerprint,
    required this.loaded,
    required this.error,
    required this.selfSigned,
  });

  factory DesktopCertInfo.fromJson(Map<String, Object?> json) =>
      DesktopCertInfo(
        source: '${json['source'] ?? ''}',
        subject: '${json['subject'] ?? ''}',
        issuer: '${json['issuer'] ?? ''}',
        notAfter: '${json['notAfter'] ?? ''}',
        dnsNames: _strings(json['dnsNames']),
        ipAddresses: _strings(json['ipAddresses']),
        daysRemaining: _int(json['daysRemaining']),
        fingerprint: '${json['fingerprint'] ?? ''}',
        loaded: _bool(json['loaded']),
        error: '${json['error'] ?? ''}',
        selfSigned: _bool(json['selfSigned']),
      );

  static const empty = DesktopCertInfo(
    source: '',
    subject: '',
    issuer: '',
    notAfter: '',
    dnsNames: [],
    ipAddresses: [],
    daysRemaining: 0,
    fingerprint: '',
    loaded: false,
    error: '',
    selfSigned: false,
  );

  final String source;
  final String subject;
  final String issuer;
  final String notAfter;
  final List<String> dnsNames;
  final List<String> ipAddresses;
  final int daysRemaining;
  final String fingerprint;
  final bool loaded;
  final String error;
  final bool selfSigned;
}

class DesktopEncryptedStatus {
  const DesktopEncryptedStatus({
    required this.config,
    required this.cert,
    required this.certDir,
    required this.defaultDotPort,
    required this.defaultDohPort,
    required this.defaultDoqPort,
    required this.defaultDohPath,
    required this.dotListen,
    required this.dohListen,
    required this.doqListen,
    required this.dohUrls,
    required this.unrestrictedTrust,
    required this.certExpiresSoon,
    required this.certExpired,
  });

  factory DesktopEncryptedStatus.fromJson(Map<String, Object?> json) =>
      DesktopEncryptedStatus(
        config: DesktopEncryptedConfig.fromJson(_map(json['config'])),
        cert: DesktopCertInfo.fromJson(_map(json['cert'])),
        certDir: '${json['certDir'] ?? ''}',
        defaultDotPort: _int(json['defaultDotPort']),
        defaultDohPort: _int(json['defaultDohPort']),
        defaultDoqPort: _int(json['defaultDoqPort']),
        defaultDohPath: '${json['defaultDohPath'] ?? ''}',
        dotListen: '${json['dotListen'] ?? ''}',
        dohListen: '${json['dohListen'] ?? ''}',
        doqListen: '${json['doqListen'] ?? ''}',
        dohUrls: _strings(json['dohUrls']),
        unrestrictedTrust: _bool(json['unrestrictedTrust']),
        certExpiresSoon: _bool(json['certExpiresSoon']),
        certExpired: _bool(json['certExpired']),
      );

  final DesktopEncryptedConfig config;
  final DesktopCertInfo cert;
  final String certDir;
  final int defaultDotPort;
  final int defaultDohPort;
  final int defaultDoqPort;
  final String defaultDohPath;

  /// The address each listener actually bound, or empty when it is not listening.
  final String dotListen;
  final String dohListen;
  final String doqListen;

  /// Ready-to-use DoH URLs, one per server name / interface.
  final List<String> dohUrls;

  /// A trusted source of `0.0.0.0/0` or `::/0` lets anyone forge the forwarded address.
  final bool unrestrictedTrust;
  final bool certExpiresSoon;
  final bool certExpired;
}
