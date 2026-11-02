part of 'adblock_line_parser.dart';

/// Rule dedupe keys. A key must include every distinguishing dimension (`important`, `appScope`,
/// `appInverted`), or distinct rules would merge.
String blockRuleKey(
  String pattern, {
  required bool important,
  String? appScope,
  bool appInverted = false,
  String? denyallow,
  bool isRegex = false,
  String? dnsType,
}) => _ruleKey(
  'block',
  pattern,
  important: important,
  appScope: appScope,
  appInverted: appInverted,
  denyallow: denyallow,
  isRegex: isRegex,
  dnsType: dnsType,
);

String allowRuleKey(
  String pattern, {
  required bool important,
  String? appScope,
  bool appInverted = false,
  String? denyallow,
  bool isRegex = false,
  String? dnsType,
}) => _ruleKey(
  'allow',
  pattern,
  important: important,
  appScope: appScope,
  appInverted: appInverted,
  denyallow: denyallow,
  isRegex: isRegex,
  dnsType: dnsType,
);

String rewriteRuleKey(String pattern, String targetType, String targetValue) =>
    'rewrite:$pattern:$targetType:$targetValue';

String _ruleKey(
  String prefix,
  String pattern, {
  required bool important,
  String? appScope,
  required bool appInverted,
  String? denyallow,
  required bool isRegex,
  String? dnsType,
}) {
  final base = '$prefix:$pattern:$important:$appScope:$appInverted';
  final hasExtra =
      (denyallow != null && denyallow.isNotEmpty) ||
      isRegex ||
      (dnsType != null && dnsType.isNotEmpty);
  if (!hasExtra) {
    return base;
  }
  return '$base:${denyallow ?? ''}:$isRegex:${dnsType ?? ''}';
}

String blockKeyOf(ParsedRule rule) => blockRuleKey(
  rule.pattern,
  important: rule.important,
  appScope: rule.appScope,
  appInverted: rule.appInverted,
  denyallow: rule.denyallow,
  isRegex: rule.isRegex,
  dnsType: rule.dnsType,
);

String allowKeyOf(ParsedRule rule) => allowRuleKey(
  rule.pattern,
  important: rule.important,
  appScope: rule.appScope,
  appInverted: rule.appInverted,
  denyallow: rule.denyallow,
  isRegex: rule.isRegex,
  dnsType: rule.dnsType,
);

String rewriteKeyOf(ParsedRewriteRule rule) =>
    rewriteRuleKey(rule.pattern, rule.targetType, rule.targetValue);
