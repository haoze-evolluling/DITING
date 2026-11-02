/// The `User-Agent` every client in this app sends, so the page under `/config/user-agents` is a
/// real setting rather than a stored preference nothing reads.
library;

/// Sent when the user chose "不覆写"; the engine and most servers only need *a* UA.
const appFallbackUserAgent = 'DITING-Android';

/// The selected agent, or [appFallbackUserAgent] when nothing usable is selected. An empty string
/// is treated as "no override": the store writes one to tell it apart from an unset key.
String resolveRequestUserAgent(String? selected) {
  final trimmed = selected?.trim() ?? '';
  return trimmed.isEmpty ? appFallbackUserAgent : trimmed;
}
