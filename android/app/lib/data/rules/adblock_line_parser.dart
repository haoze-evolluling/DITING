/// Single-line rule parsing: cosmetic, URL, modifier and domain forms. The check order is semantic
/// and must not be reordered.
library;

import 'package:diting_android/data/rules/rule_domain_utils.dart';
import 'package:diting_android/data/rules/rule_models.dart';

part 'adblock_rule_keys.dart';

/// Element-hiding delimiters, longest first: `#$@#` is the exception form of `#$#`, so the short
/// one first would demote the rule.
const _cosmeticDelimiters = ['#\$@#', '#@#', '##', '#?#', '#\$#'];

/// Whether the line uses an element-hiding delimiter. Must run before comment filtering: a `#` line
/// may be a comment or a rule.
bool isCosmeticRuleLine(String line) => _cosmeticDelimiters.any(line.contains);

/// Index where a trailing `#` comment may start, or 0. A regex may contain `#` (`/foo#bar/`), so
/// the scan starts after the closing `/`.
int _commentSearchStart(String line, bool allow) {
  final offset = (allow && line.startsWith('@@')) ? 2 : 0;
  if (line.length <= offset + 1 || line[offset] != '/') {
    return 0;
  }
  var tokenEnd = offset + 1;
  while (tokenEnd < line.length && line[tokenEnd].trim().isNotEmpty) {
    tokenEnd++;
  }
  final closing = line.lastIndexOf('/', tokenEnd - 1);
  return closing <= offset ? 0 : closing + 1;
}

CategorizedLine parseAdblockOrDomainLine(
  String line,
  String originalLine,
  bool allow,
) {
  final cosmetic = _parseCosmeticLine(line, originalLine);
  if (cosmetic != null) {
    return cosmetic;
  }

  // Only a `#` that starts a trailing comment may be dropped: truncating at a `#` glued to the
  // pattern would widen the rule to a whole domain block.
  final hashIndex = line.indexOf('#', _commentSearchStart(line, allow));
  var value = hashIndex < 0 ? line.trim() : '';
  if (hashIndex >= 0) {
    final before = line.substring(0, hashIndex);
    if (before.isEmpty || before[before.length - 1].trim().isEmpty) {
      value = before.trim();
    } else {
      return const CategorizedLine(unsupportedCount: 1);
    }
  }
  if (value.isEmpty) {
    return const CategorizedLine(invalidCount: 1);
  }
  if (allow) {
    value = value.startsWith('@@') ? value.substring(2) : value;
  }

  var isRegex = false;
  String? regexPattern;
  String? modifiersStr;

  if (value.startsWith('/')) {
    final lastSlash = value.lastIndexOf('/');
    if (lastSlash <= 0) {
      return const CategorizedLine(invalidCount: 1);
    }
    final extractedRegex = value.substring(1, lastSlash).trim();
    if (extractedRegex.isEmpty) {
      return const CategorizedLine(invalidCount: 1);
    }
    if (!_isValidRegex(extractedRegex)) {
      return const CategorizedLine(invalidCount: 1);
    }
    isRegex = true;
    regexPattern = extractedRegex;
    final tail = value.substring(lastSlash + 1).trim();
    if (tail.isNotEmpty) {
      if (!tail.startsWith(r'$')) {
        return const CategorizedLine(invalidCount: 1);
      }
      modifiersStr = tail.substring(1);
    }
    value = '';
  }

  if (!isRegex) {
    final modifierIndex = value.indexOf(r'$');
    if (modifierIndex >= 0) {
      modifiersStr = value.substring(modifierIndex + 1);
      value = value.substring(0, modifierIndex).trim();
    }
  }

  var important = false;
  String? appScope;
  var appInverted = false;
  String? dnsrewriteTargetType;
  String? dnsrewriteTargetValue;
  var dnsrewriteIsBlock = false;
  var isBadfilter = false;
  String? denyallow;
  String? dnsType;

  if (modifiersStr != null && modifiersStr.isNotEmpty) {
    final modifiers = modifiersStr
        .split(',')
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty);
    for (final token in modifiers) {
      final lower = token.toLowerCase();
      if (lower == 'important') {
        important = true;
      } else if (lower.startsWith('~denyallow=')) {
        // The modifier is already an exclusion list, so `~` is dropped but the rule is kept, as the
        // desktop parser does.
        continue;
      } else if (lower.startsWith('app=') || lower.startsWith('~app=')) {
        final isNegativePrefix = lower.startsWith('~app=');
        final appValue = isNegativePrefix
            ? token.substring(5).trim()
            : token.substring(4).trim();
        if (appValue.isEmpty) {
          return const CategorizedLine(unsupportedCount: 1);
        }
        final pkgs = appValue
            .split('|')
            .map((pkg) => pkg.trim())
            .where((pkg) => pkg.isNotEmpty)
            .toList();
        if (pkgs.isEmpty) {
          return const CategorizedLine(unsupportedCount: 1);
        }
        final hasInverted =
            isNegativePrefix || pkgs.any((pkg) => pkg.startsWith('~'));
        final cleanPkgs = pkgs
            .map(
              (pkg) => (pkg.startsWith('~') ? pkg.substring(1) : pkg)
                  .trim()
                  .toLowerCase(),
            )
            .where((pkg) => pkg.isNotEmpty)
            .toList();
        if (cleanPkgs.isEmpty) {
          return const CategorizedLine(unsupportedCount: 1);
        }
        appInverted = hasInverted;
        appScope = cleanPkgs.join('|');
      } else if (lower.startsWith('denyallow=')) {
        final rawSpec = token.substring(10).trim();
        if (rawSpec.isEmpty) {
          return const CategorizedLine(invalidCount: 1);
        }
        final rawDomains = rawSpec
            .split('|')
            .map((domain) => domain.trim().toLowerCase())
            .where((domain) => domain.isNotEmpty)
            .toList();
        if (rawDomains.isEmpty) {
          return const CategorizedLine(invalidCount: 1);
        }
        final cleanDomains = <String>[];
        for (final domain in rawDomains) {
          var clean = domain.startsWith('||') ? domain.substring(2) : domain;
          clean = clean.replaceFirst(RegExp(r'\^+$'), '');
          clean = clean.replaceFirst(RegExp(r'\.+$'), '');
          final normalized = normalizeDomain(clean);
          if (normalized == null) {
            return const CategorizedLine(invalidCount: 1);
          }
          cleanDomains.add(normalized);
        }
        denyallow = cleanDomains.join('|');
      } else if (lower.startsWith('dnstype=') ||
          lower.startsWith('~dnstype=')) {
        final isNegative = lower.startsWith('~dnstype=');
        final rawSpec = (isNegative ? token.substring(9) : token.substring(8))
            .trim();
        if (rawSpec.isEmpty) {
          return const CategorizedLine(unsupportedCount: 1);
        }
        final rawTypes = rawSpec
            .split('|')
            .map((type) => type.trim().toUpperCase())
            .where((type) => type.isNotEmpty)
            .toList();
        if (rawTypes.isEmpty) {
          return const CategorizedLine(unsupportedCount: 1);
        }
        final cleanTypes = <String>[];
        for (final type in rawTypes) {
          final actual = type.startsWith('~') ? type.substring(1) : type;
          if (!validDnsTypes.contains(actual)) {
            return const CategorizedLine(unsupportedCount: 1);
          }
          cleanTypes.add(actual);
        }
        dnsType = (isNegative || rawTypes.any((type) => type.startsWith('~')))
            ? '~${cleanTypes.join('|')}'
            : cleanTypes.join('|');
      } else if (lower.startsWith('dnsrewrite=')) {
        final rawSpec = token.substring(11).trim();
        if (rawSpec.isEmpty) {
          return const CategorizedLine(invalidCount: 1);
        }
        final targetSpec = rawSpec.contains(';')
            ? _dnsrewriteLastPart(rawSpec)
            : rawSpec;
        final upper = targetSpec.toUpperCase();
        final lowerTarget = targetSpec.toLowerCase();
        if (upper == 'NXDOMAIN' ||
            upper == 'REFUSED' ||
            upper == 'SERVFAIL' ||
            sinkholeAddresses.contains(lowerTarget)) {
          dnsrewriteIsBlock = true;
        } else if (looksLikeLiteralIp(targetSpec)) {
          final address = InternetAddressParse.numeric(targetSpec);
          if (address == null) {
            return const CategorizedLine(invalidCount: 1);
          }
          dnsrewriteTargetType = address.contains(':')
              ? RewriteTargetType.ipv6
              : RewriteTargetType.ipv4;
          dnsrewriteTargetValue = address;
        } else {
          final cname = normalizeDomain(targetSpec);
          if (cname == null) {
            return const CategorizedLine(invalidCount: 1);
          }
          dnsrewriteTargetType = RewriteTargetType.cname;
          dnsrewriteTargetValue = cname;
        }
      } else if (lower == 'badfilter') {
        isBadfilter = true;
      } else if (isWebOnlyModifier(lower)) {
        return const CategorizedLine(ignoredCount: 1);
      } else if (lower == 'all' || lower == 'empty') {
        // `$all` matches every content type: no extra constraint at DNS level.
      } else {
        return const CategorizedLine(unsupportedCount: 1);
      }
    }
  }

  if (!isRegex && _isUrlOrPathRule(value)) {
    final cleanPattern = _cleanUrlPattern(value);
    if (cleanPattern.isNotEmpty) {
      if (isBadfilter) {
        final key = allow
            ? 'url_allow:$cleanPattern:$appScope'
            : 'url_block:$cleanPattern:$appScope';
        return CategorizedLine(badfilterKeys: {key});
      }
      final urlRule = ParsedUrlRule(
        pattern: cleanPattern,
        rawLine: originalLine,
        isAllow: allow,
        appScope: appScope,
        important: important,
      );
      return allow
          ? CategorizedLine(urlAllowRules: [urlRule])
          : CategorizedLine(urlBlockRules: [urlRule]);
    }
  }

  final String domain;
  final bool isWildcard;
  if (isRegex) {
    domain = regexPattern!;
    isWildcard = false;
  } else {
    if (value.startsWith('||')) {
      value = value.replaceFirst(RegExp(r'\^+$'), '').substring(2);
    } else if (value.startsWith('|') || value.endsWith('|')) {
      return const CategorizedLine(unsupportedCount: 1);
    } else {
      value = value.replaceFirst(RegExp(r'\^+$'), '');
    }
    isWildcard = value.contains('*');
    final normalized = isWildcard
        ? normalizeWildcardDomain(value)
        : normalizeDomain(value);
    if (normalized == null) {
      return const CategorizedLine(invalidCount: 1);
    }
    domain = normalized;
  }

  if (isBadfilter) {
    final String key;
    if (dnsrewriteTargetType != null && dnsrewriteTargetValue != null) {
      key = rewriteRuleKey(domain, dnsrewriteTargetType, dnsrewriteTargetValue);
    } else if (dnsrewriteIsBlock || !allow) {
      key = blockRuleKey(
        domain,
        important: important,
        appScope: appScope,
        appInverted: appInverted,
        denyallow: denyallow,
        isRegex: isRegex,
        dnsType: dnsType,
      );
    } else {
      key = allowRuleKey(
        domain,
        important: important,
        appScope: appScope,
        appInverted: appInverted,
        denyallow: denyallow,
        isRegex: isRegex,
        dnsType: dnsType,
      );
    }
    return CategorizedLine(badfilterKeys: {key});
  }

  if (dnsrewriteTargetType != null && dnsrewriteTargetValue != null) {
    return CategorizedLine(
      rewriteRules: [
        ParsedRewriteRule(
          pattern: domain,
          targetType: dnsrewriteTargetType,
          targetValue: dnsrewriteTargetValue,
          rawLine: originalLine,
        ),
      ],
    );
  }

  final rule = ParsedRule(
    pattern: domain,
    rawLine: originalLine,
    important: important,
    appScope: appScope,
    appInverted: appInverted,
    isWildcard: isWildcard,
    denyallow: denyallow,
    isRegex: isRegex,
    dnsType: dnsType,
  );
  if (dnsrewriteIsBlock) {
    return CategorizedLine(blockRules: [rule]);
  }
  return allow
      ? CategorizedLine(allowRules: [rule])
      : CategorizedLine(blockRules: [rule]);
}

/// `dnsrewrite=a;b;c` takes the last part; a leading NXDOMAIN/REFUSED/SERVFAIL means a blackhole.
String _dnsrewriteLastPart(String rawSpec) {
  final parts = rawSpec
      .split(';')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return rawSpec;
  }
  final first = parts.first.toUpperCase();
  if (first == 'NXDOMAIN' || first == 'REFUSED' || first == 'SERVFAIL') {
    return 'NXDOMAIN';
  }
  return parts.last;
}

CategorizedLine? _parseCosmeticLine(String line, String originalLine) {
  final isException = line.contains('#@#') || line.contains(r'#$@#');
  final String delimiter;
  if (line.contains(r'#$@#')) {
    delimiter = r'#$@#';
  } else if (line.contains('#@#')) {
    delimiter = '#@#';
  } else if (line.contains('##')) {
    delimiter = '##';
  } else if (line.contains('#?#')) {
    delimiter = '#?#';
  } else if (line.contains(r'#$#')) {
    delimiter = r'#$#';
  } else {
    return null;
  }

  final index = line.indexOf(delimiter);
  final domainPart = line.substring(0, index).trim();
  final selectorPart = line.substring(index + delimiter.length).trim();
  if (selectorPart.isEmpty) {
    return const CategorizedLine(invalidCount: 1);
  }
  final domains = domainPart.isEmpty
      ? ['']
      : domainPart
            .split(',')
            .map((domain) => domain.trim())
            .where((domain) => domain.isNotEmpty)
            .toList();
  if (domains.isEmpty) {
    return const CategorizedLine(invalidCount: 1);
  }
  return CategorizedLine(
    cosmeticRules: [
      for (final domain in domains)
        ParsedCosmeticRule(
          domain: domain,
          selector: selectorPart,
          rawLine: originalLine,
          isException: isException,
        ),
    ],
  );
}

bool _isUrlOrPathRule(String value) {
  final lower = value.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return true;
  }
  if (lower.startsWith('|http://') || lower.startsWith('|https://')) {
    return true;
  }
  // ||domain/path^ or ||*/path^
  if (value.startsWith('||') && value.substring(2).contains('/')) {
    return true;
  }
  if (value.startsWith('*/') && value.length > 2) {
    return true;
  }
  if (value.startsWith('/') && !value.endsWith('/') && value.length > 2) {
    return true;
  }
  return false;
}

String _cleanUrlPattern(String value) {
  var cleaned = value.startsWith('||') ? value.substring(2) : value;
  if (cleaned.startsWith('|')) {
    cleaned = cleaned.substring(1);
  }
  cleaned = cleaned.replaceFirst(RegExp(r'\^+$'), '');
  return cleaned.trim();
}

/// Dart's `RegExp` has no validate-only constructor; compiling is the check.
bool _isValidRegex(String pattern) {
  try {
    RegExp(pattern);
    return true;
  } on FormatException {
    return false;
  }
}

class InternetAddressParse {
  const InternetAddressParse._();

  static String? numeric(String value) => parseNumericAddressSafe(value);
}
