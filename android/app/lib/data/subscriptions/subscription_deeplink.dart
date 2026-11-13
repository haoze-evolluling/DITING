/// Parses the external subscription-import deep link
/// `diting://install-config?url=<encoded http(s) URL>` (with `install-sub` as an alias).
///
/// Kept as a pure function so it needs no native channel and the accepted grammar is easy to test.
/// The address itself is validated by the add form on submit, which also reports the localized
/// error; here only the link shape and a basic HTTP(S) check are enforced.
library;

/// Hosts accepted for the subscription-import deep link.
const subscriptionDeepLinkHosts = {'install-config', 'install-sub'};

String? parseSubscriptionDeepLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() != 'diting') return null;
  if (!subscriptionDeepLinkHosts.contains(uri.host.toLowerCase())) return null;
  final url = uri.queryParameters['url']?.trim() ?? '';
  if (!_isHttpUrl(url)) return null;
  return url;
}

bool _isHttpUrl(String value) {
  if (value.isEmpty) return false;
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
  return uri.scheme.toLowerCase() == 'http' || uri.scheme.toLowerCase() == 'https';
}
