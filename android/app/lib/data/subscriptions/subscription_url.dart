/// Subscription URL and mirror helpers. The rules — placeholder set, Java `URLEncoder` spelling,
/// replacement order, validation order and the lexical line count — live in
/// `rust/diting-subscription-core/src/url.rs`; this file keeps `Uri` parsing and the localised
/// sentences.
library;

import 'package:diting_shared/app/l10n/l10n.dart';

import 'package:diting_android/data/subscriptions/rust_subscription_core.dart';

/// Persisted accepted placeholders, also used for the error sentence.
const mirrorPlaceholders = <String>{
  '{url}',
  '{urlEncoded}',
  '{scheme}',
  '{host}',
  '{path}',
  '{pathAndQuery}',
};

const _placeholderList =
    '{url}、{urlEncoded}、{scheme}、{host}、{path} 或 {pathAndQuery}';

RustSubscriptionCore get _core => RustSubscriptionCore.instance;

String _urlErrorText(String kind) => switch (kind) {
  'empty' => currentL10n.subsErrEmpty,
  'notHttp' => currentL10n.subsErrNotHttp,
  'noHost' => currentL10n.subsErrNoHost,
  _ => currentL10n.subsErrBadFormat,
};

String _mirrorErrorText(String kind) => switch (kind) {
  'placeholder' => currentL10n.subsErrMirrorPlaceholder(_placeholderList),
  'rawUrl' => currentL10n.subsErrRawUrlInvalid,
  _ => currentL10n.subsErrMirrorScheme,
};

String? _errorOf(Map<String, Object?> answer) => answer['error'] as String?;

/// One sentence for every token the add/edit forms and the mirror helpers can return.
String subscriptionFormErrorText(String kind) => switch (kind) {
  'pickFile' => currentL10n.subscriptionPickRuleFile,
  'pickTxt' => currentL10n.subscriptionPickTxtFile,
  'placeholder' => currentL10n.subsErrMirrorPlaceholder(_placeholderList),
  'scheme' => currentL10n.subsErrMirrorScheme,
  'rawUrl' => currentL10n.subsErrRawUrlInvalid,
  _ => _urlErrorText(kind),
};

/// URI components for address rules; the path stays exactly what [Uri] normalised.
Map<String, Object?> _partsOf(Uri? uri) => uriParts(uri);

/// URI components for mirror building: an empty path is `/`, matching the legacy path join. The
/// downloader also uses this, so the request it plans and the preview it shows agree.
Map<String, Object?> mirrorUrlParts(Uri? uri) {
  final parts = uriParts(uri);
  if ((parts['path'] as String).isEmpty) parts['path'] = '/';
  return parts;
}

/// Validates and normalizes a mirror template. Null means no template; a malformed one throws
/// [FormatException] for the edit panel to report.
String? normalizeMirrorTemplate(String? template) {
  final answer = _core.call({'op': 'url.normalize', 'template': template});
  final error = _errorOf(answer);
  if (error != null) throw FormatException(_mirrorErrorText(error));
  return answer['template'] as String?;
}

/// Builds the mirror URL from a template. `{urlEncoded}` follows Java `URLEncoder` (keeps `*`,
/// encodes `~`), not `Uri.encodeComponent`.
String buildMirrorUrl(String template, String originalUrl) {
  final uri = Uri.tryParse(originalUrl);
  if (uri == null) {
    throw FormatException(currentL10n.subsErrRawUrlInvalid);
  }
  final answer = _core.call({
    'op': 'url.build',
    'template': template,
    'url': originalUrl,
    'urlParts': mirrorUrlParts(uri),
  });
  final error = _errorOf(answer);
  if (error != null) throw FormatException(_mirrorErrorText(error));
  return answer['url']! as String;
}

String extractNameFromUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final answer = _core.call({
    'op': 'url.name',
    'url': url,
    'path': uri.path,
    'host': uri.host,
  });
  return answer['name'] as String? ?? url;
}

/// Lexically counts effective lines (non-empty, non-comment): a download-layer figure, not the
/// imported rule count.
int countEffectiveRuleLines(String content) {
  final answer = _core.call({'op': 'url.lines', 'content': content});
  return (answer['count'] as num?)?.toInt() ?? 0;
}

/// Basic URL validation: an absolute HTTP(S) URL with a host. Null means valid, otherwise the
/// returned text is shown to the user.
String? validateSubscriptionUrl(String url) {
  final trimmed = url.trim();
  final answer = _core.call({
    'op': 'url.validate',
    'url': trimmed,
    'urlParts': _partsOf(Uri.tryParse(trimmed)),
  });
  final error = _errorOf(answer);
  return error == null ? null : _urlErrorText(error);
}
