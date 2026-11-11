/// IP quality check: queries several public IP intelligence sources in parallel and merges their
/// answers into one report.
///
/// HTTP, timeouts and the localized failure sentences stay here; the egress-IP gate, every source
/// field, the type keywords and the report summary come from `rust/diting-ip-quality-core`, so
/// there is no second classifier to drift.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:diting_android/data/db/rust_ip_quality_core.dart';
import 'package:diting_android/data/http/request_user_agent.dart';
import 'package:diting_shared/app/l10n/l10n.dart';

class IpSourceResult {
  const IpSourceResult({
    required this.name,
    required this.status,
    this.ipType,
    this.latencyMs,
    this.detail,
    this.organization,
    this.asn,
  });

  final String name;

  final String status;

  /// Source-reported type (residential/mobile/business/datacenter), null if unknown.
  final String? ipType;
  final int? latencyMs;

  final String? detail;

  final String? organization;

  final String? asn;

  bool get isHit => status == '命中';
}

class IpQualityReport {
  const IpQualityReport({
    required this.ip,
    required this.ipType,
    required this.level,
    required this.organization,
    required this.asn,
    required this.sources,
  });

  final String ip;
  final String ipType;

  final String level;
  final String organization;
  final String asn;
  final List<IpSourceResult> sources;

  int get hitCount => sources.where((s) => s.isHit).length;
}

class IpQualityFailure {
  const IpQualityFailure(this.message);

  final String message;
}

sealed class IpQualityOutcome {
  const IpQualityOutcome();
}

class IpQualitySuccess extends IpQualityOutcome {
  const IpQualitySuccess(this.report);

  final IpQualityReport report;
}

class IpQualityError extends IpQualityOutcome {
  const IpQualityError(this.failure);

  final IpQualityFailure failure;
}

class IpQualityChecker {
  const IpQualityChecker({
    this.timeout = const Duration(seconds: 6),
    this.probeUrls = const [
      'https://api64.ipify.org?format=json',
      'https://api.ip.sb/ip',
      'https://ifconfig.me/ip',
    ],
    this.ipApiUrl = 'http://ip-api.com/json',
    this.ipWhoIsUrl = 'https://ipwho.is',
    this.ipInfoUrl = 'https://ipinfo.io',
    this.userAgent = appFallbackUserAgent,
  });

  final Duration timeout;

  /// `/config/user-agents` override; public IP-intel endpoints throttle unknown agents.
  final String userAgent;

  /// Ordered fallback chain of "what is my egress IP" probes. Measured, not read from the NIC: the
  /// user cares about the tunnel exit, not the LAN IP.
  final List<String> probeUrls;

  final String ipApiUrl;
  final String ipWhoIsUrl;
  final String ipInfoUrl;

  Future<IpQualityOutcome> detect() async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final probe = await _myIp(client);
      if (probe == null) {
        return IpQualityError(IpQualityFailure(currentL10n.ipQualityNoExitIp));
      }
      final sources = await _querySources(client, probe);
      if (sources.every((source) => !source.isHit)) {
        return IpQualityError(
          IpQualityFailure(currentL10n.ipQualityNoSourceResult),
        );
      }
      return IpQualitySuccess(_summarize(probe, sources));
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _myIp(HttpClient client) async {
    for (final url in probeUrls) {
      final ip = await _fetchIp(client, url);
      if (ip != null) return ip;
    }
    return null;
  }

  Future<String?> _fetchIp(HttpClient client, String url) async {
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      return RustIpQualityCore.instance.parseProbe(body);
    } on StateError {
      // The native core missing or rejecting a payload is a build error, not a source failure.
      rethrow;
    } on Object {
      return null;
    }
  }

  Future<List<IpSourceResult>> _querySources(
    HttpClient client,
    String ip,
  ) async {
    final probes = <Future<IpSourceResult>>[
      _ipApi(client, ip),
      _ipWhoIs(client, ip),
      _ipInfo(client, ip),
    ];
    return Future.wait(probes);
  }

  /// ip-api.com: free, no key, plain HTTP (TLS there is a paid feature).
  Future<IpSourceResult> _ipApi(HttpClient client, String ip) => _get(
    client,
    'ipApi',
    'ip-api.com',
    '$ipApiUrl/$ip?fields=status,message,as,isp,org',
  );

  Future<IpSourceResult> _ipWhoIs(HttpClient client, String ip) =>
      _get(client, 'ipWhoIs', 'ipwho.is', '$ipWhoIsUrl/$ip');

  /// ipinfo.io: limited free quota; org looks like `AS15169 Google LLC`.
  Future<IpSourceResult> _ipInfo(HttpClient client, String ip) =>
      _get(client, 'ipInfo', 'ipinfo.io', '$ipInfoUrl/$ip/json');

  Future<IpSourceResult> _get(
    HttpClient client,
    String source,
    String name,
    String url,
  ) async {
    final watch = Stopwatch()..start();
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      watch.stop();
      final row = RustIpQualityCore.instance.sourceResult(
        source: source,
        status: response.statusCode,
        body: body,
      );
      return IpSourceResult(
        name: name,
        status: row['status'] as String? ?? '失败',
        ipType: row['ipType'] as String?,
        latencyMs: watch.elapsedMilliseconds,
        detail: row['detail'] as String?,
        organization: row['organization'] as String?,
        asn: row['asn'] as String?,
      );
    } on TimeoutException {
      return IpSourceResult(name: name, status: '超时');
    } on SocketException {
      return IpSourceResult(name: name, status: '超时', detail: '无法连接');
    } on FormatException {
      return IpSourceResult(name: name, status: '失败', detail: '响应不是合法 JSON');
    } on StateError {
      // The native core missing or rejecting a payload is a build error, not a source failure.
      rethrow;
    } on Object catch (error) {
      return IpSourceResult(name: name, status: '失败', detail: '$error');
    }
  }

  static IpQualityReport _summarize(String ip, List<IpSourceResult> sources) {
    final summary = RustIpQualityCore.instance.summarize(ip, [
      for (final source in sources)
        {
          'status': source.status,
          'ipType': source.ipType,
          'organization': source.organization,
          'asn': source.asn,
        },
    ]);
    return IpQualityReport(
      ip: ip,
      ipType: summary['ipType'] as String? ?? '商业',
      level: summary['level'] as String? ?? '一般',
      organization: summary['organization'] as String? ?? '',
      asn: summary['asn'] as String? ?? '',
      sources: sources,
    );
  }
}
