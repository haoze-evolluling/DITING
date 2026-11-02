/// Models for parsed AdGuard, ABP, hosts and dnsmasq rules. Cosmetic rules are parsed but never
/// stored; see [CategorizedLine.cosmeticRules].
library;

class RewriteTargetType {
  const RewriteTargetType._();

  static const ipv4 = 'IPv4';
  static const ipv6 = 'IPv6';
  static const cname = 'CNAME';
}

class ParsedRule {
  const ParsedRule({
    required this.pattern,
    required this.rawLine,
    this.important = false,
    this.appScope,
    this.appInverted = false,
    this.isWildcard = false,
    this.denyallow,
    this.isRegex = false,
    this.dnsType,
  });

  final String pattern;
  final String rawLine;
  final bool important;
  final String? appScope;
  final bool appInverted;
  final bool isWildcard;
  final String? denyallow;
  final bool isRegex;
  final String? dnsType;
}

class ParsedUrlRule {
  const ParsedUrlRule({
    required this.pattern,
    required this.rawLine,
    this.isAllow = false,
    this.appScope,
    this.important = false,
  });

  final String pattern;
  final String rawLine;
  final bool isAllow;
  final String? appScope;
  final bool important;
}

class ParsedCosmeticRule {
  const ParsedCosmeticRule({
    required this.domain,
    required this.selector,
    required this.rawLine,
    this.isException = false,
  });

  final String domain;
  final String selector;
  final String rawLine;
  final bool isException;

  String toCss() => '$selector { display: none !important; }';
}

class ParsedRewriteRule {
  const ParsedRewriteRule({
    required this.pattern,
    required this.targetType,
    required this.targetValue,
    required this.rawLine,
  });

  final String pattern;
  final String targetType;
  final String targetValue;
  final String rawLine;
}

/// Result of parsing one line; one line may expand into several rules.
class CategorizedLine {
  const CategorizedLine({
    this.blockRules = const [],
    this.allowRules = const [],
    this.rewriteRules = const [],
    this.urlBlockRules = const [],
    this.urlAllowRules = const [],
    this.cosmeticRules = const [],
    this.badfilterKeys = const {},
    this.invalidCount = 0,
    this.unsupportedCount = 0,
    this.ignoredCount = 0,
  });

  final List<ParsedRule> blockRules;
  final List<ParsedRule> allowRules;
  final List<ParsedRewriteRule> rewriteRules;
  final List<ParsedUrlRule> urlBlockRules;
  final List<ParsedUrlRule> urlAllowRules;
  final List<ParsedCosmeticRule> cosmeticRules;
  final Set<String> badfilterKeys;
  final int invalidCount;
  final int unsupportedCount;
  final int ignoredCount;

  bool get isEmpty =>
      blockRules.isEmpty &&
      allowRules.isEmpty &&
      rewriteRules.isEmpty &&
      urlBlockRules.isEmpty &&
      urlAllowRules.isEmpty &&
      cosmeticRules.isEmpty;
}

class CategorizedRules {
  const CategorizedRules({
    this.blockRules = const [],
    this.allowRules = const [],
    this.rewriteRules = const [],
    this.urlBlockRules = const [],
    this.urlAllowRules = const [],
    this.cosmeticRules = const [],
    this.duplicateCount = 0,
    this.invalidCount = 0,
    this.unsupportedCount = 0,
    this.ignoredCount = 0,
    this.badfilteredCount = 0,
    this.totalLines = 0,
  });

  final List<ParsedRule> blockRules;
  final List<ParsedRule> allowRules;
  final List<ParsedRewriteRule> rewriteRules;
  final List<ParsedUrlRule> urlBlockRules;
  final List<ParsedUrlRule> urlAllowRules;
  final List<ParsedCosmeticRule> cosmeticRules;
  final int duplicateCount;
  final int invalidCount;
  final int unsupportedCount;
  final int ignoredCount;
  final int badfilteredCount;
  final int totalLines;

  int get size =>
      blockRules.length +
      allowRules.length +
      rewriteRules.length +
      urlBlockRules.length +
      urlAllowRules.length +
      cosmeticRules.length;

  int get skippedCount => invalidCount + unsupportedCount;

  bool get isEmpty => size == 0;
}
