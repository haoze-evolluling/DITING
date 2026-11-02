/// Parser for the preset passthrough whitelist asset; seeded rows must match the legacy seeder:
/// domains lowercased, trailing dot removed, first occurrence wins.
library;

typedef PresetEntry = ({String domain, String group});

const _ignoredHeaders = ['Format:', 'Comment:', 'Each entry', 'Domains in'];

List<PresetEntry> parsePresetWhitelist(String content) {
  final results = <PresetEntry>[];
  final seen = <String>{};
  var currentGroup = '默认预设';

  for (final rawLine in content.split(RegExp(r'\r?\n'))) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (trimmed.startsWith('#') || trimmed.startsWith('//')) {
      var comment = trimmed;
      while (comment.startsWith('#') || comment.startsWith('//')) {
        comment = comment.startsWith('//')
            ? comment.substring(2)
            : comment.substring(1);
      }
      final cleaned = comment.replaceAll('─', '').trim();
      if (cleaned.isNotEmpty &&
          !_ignoredHeaders.any((prefix) => cleaned.startsWith(prefix))) {
        currentGroup = cleaned;
      }
      continue;
    }
    var domain = trimmed.toLowerCase();
    while (domain.endsWith('.')) {
      domain = domain.substring(0, domain.length - 1);
    }
    if (domain.isNotEmpty && seen.add(domain)) {
      results.add((domain: domain, group: currentGroup));
    }
  }
  return results;
}
