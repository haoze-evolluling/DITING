/// Parses hosts and dnsmasq lines; the target address picks the kind: sinkhole = block, IP =
/// rewrite, domain = CNAME.
library;

import 'package:diting_android/data/rules/rule_domain_utils.dart';
import 'package:diting_android/data/rules/rule_models.dart';

/// `address=/domain/ip`, `server=/domain/ip`, `address=/domain/`.
CategorizedLine parseDnsmasqLine(String line, String originalLine) {
  var content = line;
  if (line.contains(' #')) {
    content = line.substring(0, line.indexOf(' #'));
  } else if (line.contains('\t#')) {
    content = line.substring(0, line.indexOf('\t#'));
  }
  content = content.trim();

  final withoutPrefix = content.startsWith('address=/')
      ? content.substring('address=/'.length)
      : content.substring('server=/'.length);
  final parts = withoutPrefix.split('/');
  if (parts.length < 2) {
    return const CategorizedLine(invalidCount: 1);
  }

  final target = parts.last.trim();
  final domainParts = parts
      .sublist(0, parts.length - 1)
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (domainParts.isEmpty) {
    return const CategorizedLine(invalidCount: 1);
  }

  final isSinkhole =
      target.isEmpty ||
      target == '#' ||
      sinkholeAddresses.contains(target.toLowerCase());

  if (isSinkhole) {
    final blockList = <ParsedRule>[];
    var invalidCount = 0;
    for (final domain in domainParts) {
      final isWildcard = domain.contains('*');
      final normalized = isWildcard
          ? normalizeWildcardDomain(domain)
          : normalizeDomain(domain);
      if (normalized != null) {
        blockList.add(
          ParsedRule(
            pattern: normalized,
            rawLine: originalLine,
            isWildcard: isWildcard,
          ),
        );
      } else {
        invalidCount++;
      }
    }
    if (blockList.isEmpty && invalidCount > 0) {
      return CategorizedLine(invalidCount: invalidCount);
    }
    return CategorizedLine(blockRules: blockList, invalidCount: invalidCount);
  }

  if (looksLikeLiteralIp(target)) {
    final address = parseNumericAddressSafe(target);
    if (address != null) {
      final targetType = address.contains(':')
          ? RewriteTargetType.ipv6
          : RewriteTargetType.ipv4;
      final rewriteList = <ParsedRewriteRule>[];
      var invalidCount = 0;
      for (final domain in domainParts) {
        final normalized = normalizeDomain(domain);
        if (normalized != null) {
          rewriteList.add(
            ParsedRewriteRule(
              pattern: normalized,
              targetType: targetType,
              targetValue: address,
              rawLine: originalLine,
            ),
          );
        } else {
          invalidCount++;
        }
      }
      if (rewriteList.isEmpty && invalidCount > 0) {
        return CategorizedLine(invalidCount: invalidCount);
      }
      return CategorizedLine(
        rewriteRules: rewriteList,
        invalidCount: invalidCount,
      );
    }
  }

  final targetDomain = normalizeDomain(target);
  if (targetDomain != null) {
    final rewriteList = <ParsedRewriteRule>[];
    var invalidCount = 0;
    for (final domain in domainParts) {
      final normalized = normalizeDomain(domain);
      if (normalized != null) {
        rewriteList.add(
          ParsedRewriteRule(
            pattern: normalized,
            targetType: RewriteTargetType.cname,
            targetValue: targetDomain,
            rawLine: originalLine,
          ),
        );
      } else {
        invalidCount++;
      }
    }
    if (rewriteList.isEmpty && invalidCount > 0) {
      return CategorizedLine(invalidCount: invalidCount);
    }
    return CategorizedLine(
      rewriteRules: rewriteList,
      invalidCount: invalidCount,
    );
  }

  return const CategorizedLine(invalidCount: 1);
}

/// `IP domain1 [domain2 ...]`; null when not a hosts line.
CategorizedLine? parseHostsLineDetailed(String line, String originalLine) {
  final content = line.contains('#')
      ? line.substring(0, line.indexOf('#')).trim()
      : line.trim();
  final fields = content
      .split(RegExp(r'\s+'))
      .where((field) => field.isNotEmpty)
      .toList();
  if (fields.length < 2 || !looksLikeLiteralIp(fields.first)) {
    return null;
  }

  final ipStr = fields.first.toLowerCase();
  final hosts = fields.sublist(1);
  var invalidCount = 0;

  if (sinkholeAddresses.contains(ipStr)) {
    final rules = <ParsedRule>[];
    for (final host in hosts) {
      final normalized = normalizeDomain(host);
      if (normalized != null) {
        rules.add(ParsedRule(pattern: normalized, rawLine: originalLine));
      } else {
        invalidCount++;
      }
    }
    if (rules.isEmpty && invalidCount > 0) {
      return CategorizedLine(invalidCount: invalidCount);
    }
    return CategorizedLine(blockRules: rules, invalidCount: invalidCount);
  }

  final address = parseNumericAddressSafe(fields.first);
  if (address == null) {
    return const CategorizedLine(invalidCount: 1);
  }
  final targetType = address.contains(':')
      ? RewriteTargetType.ipv6
      : RewriteTargetType.ipv4;

  final rewriteRules = <ParsedRewriteRule>[];
  for (final host in hosts) {
    final normalized = normalizeDomain(host);
    if (normalized != null) {
      rewriteRules.add(
        ParsedRewriteRule(
          pattern: normalized,
          targetType: targetType,
          targetValue: address,
          rawLine: originalLine,
        ),
      );
    } else {
      invalidCount++;
    }
  }
  if (rewriteRules.isEmpty && invalidCount > 0) {
    return CategorizedLine(invalidCount: invalidCount);
  }
  return CategorizedLine(
    rewriteRules: rewriteRules,
    invalidCount: invalidCount,
  );
}
