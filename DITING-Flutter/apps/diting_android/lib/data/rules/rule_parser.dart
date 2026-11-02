library;

import 'package:diting_android/data/rules/adblock_line_parser.dart';
import 'package:diting_android/data/rules/hosts_parser.dart';
import 'package:diting_android/data/rules/rule_models.dart';

/// Parses one line without cross-line state (for streaming imports).
CategorizedLine parseCategorizedLine(String originalLine) {
  final line = originalLine.trim().replaceFirst(RegExp('^\uFEFF'), '');
  if (line.isEmpty ||
      line.startsWith('!') ||
      _isCommentLine(line) ||
      (line.startsWith('[') && line.endsWith(']'))) {
    return const CategorizedLine(ignoredCount: 1);
  }

  if (line.startsWith('address=/') || line.startsWith('server=/')) {
    return parseDnsmasqLine(line, originalLine);
  }

  final hosts = parseHostsLineDetailed(line, originalLine);
  if (hosts != null) {
    return hosts;
  }

  final allow = line.startsWith('@@');
  return parseAdblockOrDomainLine(line, originalLine, allow);
}

/// `#` starts a comment only when the line is not element-hiding, so cosmetic delimiters must be
/// checked first.
bool _isCommentLine(String line) =>
    line.startsWith('#') && !isCosmeticRuleLine(line);

/// Scans for `$badfilter` keys; the disabler may appear before the rule it disables.
Set<String> extractBadfilterKeys(String text) {
  final keys = <String>{};
  for (final line in text.split('\n')) {
    if (!line.toLowerCase().contains('badfilter')) {
      continue;
    }
    keys.addAll(parseCategorizedLine(line).badfilterKeys);
  }
  return keys;
}

/// Parses a document, groups by family, dedupes by key. [badfilterKeys] removes matches; when null
/// it is scanned first.
CategorizedRules parseCategorized(String text, {Set<String>? badfilterKeys}) {
  final keys = badfilterKeys ?? extractBadfilterKeys(text);
  final blockRules = <String, ParsedRule>{};
  final allowRules = <String, ParsedRule>{};
  final rewriteRules = <String, ParsedRewriteRule>{};
  final urlBlockRules = <String, ParsedUrlRule>{};
  final urlAllowRules = <String, ParsedUrlRule>{};
  final cosmeticRules = <String, ParsedCosmeticRule>{};
  var duplicates = 0;
  var invalid = 0;
  var unsupported = 0;
  var ignored = 0;
  var total = 0;

  for (final originalLine in text.split('\n')) {
    total++;
    final lineResult = parseCategorizedLine(originalLine);
    invalid += lineResult.invalidCount;
    unsupported += lineResult.unsupportedCount;
    ignored += lineResult.ignoredCount;

    for (final rule in lineResult.blockRules) {
      duplicates += _addUnique(blockRules, blockKeyOf(rule), rule);
    }
    for (final rule in lineResult.allowRules) {
      duplicates += _addUnique(allowRules, allowKeyOf(rule), rule);
    }
    for (final rule in lineResult.rewriteRules) {
      duplicates += _addUnique(rewriteRules, rewriteKeyOf(rule), rule);
    }
    for (final rule in lineResult.urlBlockRules) {
      final key = 'url_block:${rule.pattern}:${rule.appScope}';
      duplicates += _addUnique(urlBlockRules, key, rule);
    }
    for (final rule in lineResult.urlAllowRules) {
      final key = 'url_allow:${rule.pattern}:${rule.appScope}';
      duplicates += _addUnique(urlAllowRules, key, rule);
    }
    for (final rule in lineResult.cosmeticRules) {
      final key =
          'cosmetic:${rule.domain}:${rule.selector}:${rule.isException}';
      duplicates += _addUnique(cosmeticRules, key, rule);
    }
  }

  var badfilteredCount = 0;
  if (keys.isNotEmpty) {
    badfilteredCount += _removeKeys(blockRules, keys);
    badfilteredCount += _removeKeys(allowRules, keys);
    badfilteredCount += _removeKeys(rewriteRules, keys);
  }

  return CategorizedRules(
    blockRules: blockRules.values.toList(),
    allowRules: allowRules.values.toList(),
    rewriteRules: rewriteRules.values.toList(),
    urlBlockRules: urlBlockRules.values.toList(),
    urlAllowRules: urlAllowRules.values.toList(),
    cosmeticRules: cosmeticRules.values.toList(),
    duplicateCount: duplicates,
    invalidCount: invalid,
    unsupportedCount: unsupported,
    ignoredCount: ignored,
    badfilteredCount: badfilteredCount,
    totalLines: total,
  );
}

/// Returns 0 on first insert and 1 on a repeat, to accumulate duplicateCount.
int _addUnique<T>(Map<String, T> map, String key, T value) {
  if (map.containsKey(key)) {
    return 1;
  }
  map[key] = value;
  return 0;
}

int _removeKeys<T>(Map<String, T> map, Set<String> keys) {
  var removed = 0;
  for (final key in keys) {
    if (map.remove(key) != null) {
      removed++;
    }
  }
  return removed;
}

ParsedRule? parseRule(String line) {
  final trimmed = line.trim().replaceFirst(RegExp('^\uFEFF'), '');
  if (trimmed.startsWith('@@')) {
    return null;
  }
  return parseCategorizedLine(line).blockRules.firstOrNull;
}

/// Parses one allow rule; a bare domain without `@@` is accepted too.
ParsedRule? parseAllowRule(String line) {
  final trimmed = line.trim().replaceFirst(RegExp('^\uFEFF'), '');
  if (!trimmed.startsWith('@@')) {
    final cat = parseAdblockOrDomainLine(trimmed, line, true);
    return cat.allowRules.firstOrNull;
  }
  return parseCategorizedLine(line).allowRules.firstOrNull;
}
