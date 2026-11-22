library;

const appFallbackUserAgent = 'DITING-Android';

String resolveRequestUserAgent(String? selected) {
  final trimmed = selected?.trim() ?? '';
  return trimmed.isEmpty ? appFallbackUserAgent : trimmed;
}
