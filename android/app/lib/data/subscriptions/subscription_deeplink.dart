library;

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
