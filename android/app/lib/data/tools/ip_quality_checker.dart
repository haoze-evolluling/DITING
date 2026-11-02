/// IP quality check: queries several public IP intelligence sources in parallel and merges their
/// answers into one report.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:diting_android/data/http/request_user_agent.dart';

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
        return IpQualityError(
          IpQualityFailure(currentL10n.ipQualityNoExitIp),
        );
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
      final raw = body.trim();
      if (raw.startsWith('{')) {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['ip'] is String) {
          final ip = (decoded['ip'] as String).trim();
          return _isIpLike(ip) ? ip : null;
        }
        return null;
      }
      return _isIpLike(raw) ? raw : null;
    } on Object {
      return null;
    }
  }

  /// Rejects HTML bodies (captive portal, rate-limit page) so they are not mistaken for an IP
  /// address.
  static bool _isIpLike(String value) {
    if (value.isEmpty || value.length > 45) return false;
    return RegExp(r'^[0-9a-fA-F:.]+$').hasMatch(value);
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
  Future<IpSourceResult> _ipApi(HttpClient client, String ip) async {
    final watch = Stopwatch()..start();
    return _get(
      client,
      'ip-api.com',
      '$ipApiUrl/$ip?fields=status,message,as,isp,org',
      (body) {
        final decoded = jsonDecode(body);
        if (decoded is! Map || decoded['status'] != 'success') {
          // Failures look like {"status":"fail","message":"private range"}.
          return _ProbeOutcome(
            status: '失败',
            detail: decoded is Map ? '${decoded['message'] ?? ''}' : null,
          );
        }
        return _ProbeOutcome(
          status: '命中',
          ipType: _classify(
            '${decoded['as'] ?? ''} ${decoded['isp'] ?? ''} ${decoded['org'] ?? ''}',
          ),
          organization: '${decoded['isp'] ?? decoded['org'] ?? ''}',
          asn: _asnOf('${decoded['as'] ?? ''}'),
        );
      },
      watch,
    );
  }

  Future<IpSourceResult> _ipWhoIs(HttpClient client, String ip) async {
    final watch = Stopwatch()..start();
    return _get(client, 'ipwho.is', '$ipWhoIsUrl/$ip', (body) {
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['success'] == false) {
        return _ProbeOutcome(
          status: '失败',
          detail: decoded is Map ? '${decoded['message'] ?? ''}' : null,
        );
      }
      final connection = decoded['connection'];
      final asnText = connection is Map ? '${connection['asn'] ?? ''}' : '';
      return _ProbeOutcome(
        status: '命中',
        ipType: _classify(
          connection is Map
              ? '${connection['isp'] ?? ''} ${connection['org'] ?? ''} ${connection['domain'] ?? ''}'
              : '',
        ),
        organization: connection is Map
            ? '${connection['isp'] ?? connection['org'] ?? ''}'
            : '',
        asn: asnText.isEmpty ? '' : 'AS$asnText',
      );
    }, watch);
  }

  /// ipinfo.io: limited free quota; org looks like `AS15169 Google LLC`.
  Future<IpSourceResult> _ipInfo(HttpClient client, String ip) async {
    final watch = Stopwatch()..start();
    return _get(client, 'ipinfo.io', '$ipInfoUrl/$ip/json', (body) {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return const _ProbeOutcome(status: '失败');
      }
      // Exhausted quota returns {"error": {...}} with status 200, not 4xx.
      if (decoded['error'] != null) {
        return _ProbeOutcome(
          status: '限流',
          detail: decoded['error'] is Map
              ? '${(decoded['error'] as Map)['message'] ?? ''}'
              : null,
        );
      }
      final org = '${decoded['org'] ?? ''}';
      return _ProbeOutcome(
        status: '命中',
        ipType: _classify(org),
        organization: _orgNameOf(org),
        asn: _asnOf(org),
      );
    }, watch);
  }

  Future<IpSourceResult> _get(
    HttpClient client,
    String name,
    String url,
    _ProbeOutcome Function(String body) parse,
    Stopwatch watch,
  ) async {
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      watch.stop();
      if (response.statusCode == 429) {
        return IpSourceResult(
          name: name,
          status: '限流',
          latencyMs: watch.elapsedMilliseconds,
        );
      }
      if (response.statusCode != 200) {
        return IpSourceResult(
          name: name,
          status: '失败',
          latencyMs: watch.elapsedMilliseconds,
          detail: 'HTTP ${response.statusCode}',
        );
      }
      final outcome = parse(body);
      return IpSourceResult(
        name: name,
        status: outcome.status,
        ipType: outcome.ipType,
        latencyMs: watch.elapsedMilliseconds,
        detail: outcome.detail,
        organization: outcome.organization,
        asn: outcome.asn,
      );
    } on TimeoutException {
      return IpSourceResult(name: name, status: '超时');
    } on SocketException {
      return IpSourceResult(name: name, status: '超时', detail: '无法连接');
    } on FormatException {
      return IpSourceResult(name: name, status: '失败', detail: '响应不是合法 JSON');
    } on Object catch (error) {
      return IpSourceResult(name: name, status: '失败', detail: '$error');
    }
  }

  /// Infers type from the org/ISP text with a keyword table, not ML.
  static String _classify(String text) {
    final lower = text.toLowerCase();
    const datacenter = [
      'hosting',
      'datacenter',
      'data center',
      'cloud',
      'server',
      'vps',
      'amazon',
      'aws',
      'google',
      'microsoft',
      'azure',
      'digitalocean',
      'linode',
      'vultr',
      'ovh',
      'hetzner',
      'cloudflare',
      'alibaba',
      'tencent',
      'leaseweb',
      'contabo',
      'oracle',
    ];
    const mobile = [
      'mobile',
      'wireless',
      'cellular',
      'china mobile',
      '中国移动',
      'china unicom',
      '中国联通',
      'china telecom',
      '中国电信',
      '4g',
      '5g',
    ];
    for (final keyword in mobile) {
      if (lower.contains(keyword)) return '移动';
    }
    for (final keyword in datacenter) {
      if (lower.contains(keyword)) return '机房';
    }
    if (lower.contains('university') || lower.contains('college')) return '商业';
    // Default to business: labelling a datacenter as residential would make the user think the IP
    // is clean.
    return '商业';
  }

  static String _asnOf(String org) {
    final match = RegExp(r'AS\d+').firstMatch(org);
    return match?.group(0) ?? '';
  }

  static String _orgNameOf(String org) {
    return org.replaceFirst(RegExp(r'^AS\d+\s*'), '').trim();
  }

  static IpQualityReport _summarize(String ip, List<IpSourceResult> sources) {
    final hits = sources.where((s) => s.isHit).toList();
    final typeCounts = <String, int>{};
    for (final hit in hits) {
      final type = hit.ipType;
      if (type == null || type.isEmpty) continue;
      typeCounts[type] = (typeCounts[type] ?? 0) + 1;
    }
    var ipType = '商业';
    if (typeCounts.isNotEmpty) {
      // Ties break toward the more severe type: datacenter > business > mobile.
      const severity = {'机房': 3, '商业': 2, '移动': 1};
      final sorted = typeCounts.entries.toList()
        ..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          if (byCount != 0) return byCount;
          return (severity[b.key] ?? 0).compareTo(severity[a.key] ?? 0);
        });
      ipType = sorted.first.key;
    }

    // Datacenter = risky (streaming and banks block it), mobile = good, business = fair.
    final level = switch (ipType) {
      '机房' => '风险',
      '移动' => '优秀',
      _ => '一般',
    };

    // First non-empty org/ASN wins: mixing sources would mislead.
    return IpQualityReport(
      ip: ip,
      ipType: ipType,
      level: level,
      organization: _firstOf(hits.map((s) => s.organization)) ?? '',
      asn: _firstOf(hits.map((s) => s.asn)) ?? '',
      sources: sources,
    );
  }

  static String? _firstOf(Iterable<String?> values) {
    for (final value in values) {
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}

class _ProbeOutcome {
  const _ProbeOutcome({
    required this.status,
    this.ipType,
    this.organization,
    this.asn,
    this.detail,
  });

  final String status;
  final String? ipType;
  final String? organization;
  final String? asn;
  final String? detail;
}
