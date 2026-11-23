library;

import 'package:diting_shared/app/l10n/l10n.dart';

import 'package:diting_android/data/subscriptions/rust_subscription_core.dart';


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

String subscriptionFormErrorText(String kind) => switch (kind) {
  'pickFile' => currentL10n.subscriptionPickRuleFile,
  'pickTxt' => currentL10n.subscriptionPickTxtFile,
  'placeholder' => currentL10n.subsErrMirrorPlaceholder(_placeholderList),
  'scheme' => currentL10n.subsErrMirrorScheme,
  'rawUrl' => currentL10n.subsErrRawUrlInvalid,
  _ => _urlErrorText(kind),
};

Map<String, Object?> mirrorUrlParts(Uri? uri) {
  final parts = uriParts(uri);
  if ((parts['path'] as String).isEmpty) parts['path'] = '/';
  return parts;
}

String? normalizeMirrorTemplate(String? template) {
  final answer = _core.call({'op': 'url.normalize', 'template': template});
  final error = _errorOf(answer);
  if (error != null) throw FormatException(_mirrorErrorText(error));
  return answer['template'] as String?;
}

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

int countEffectiveRuleLines(String content) {
  final answer = _core.call({'op': 'url.lines', 'content': content});
  return (answer['count'] as num?)?.toInt() ?? 0;
}

String? validateSubscriptionUrl(String url) {
  final trimmed = url.trim();
  final answer = _core.call({
    'op': 'url.validate',
    'url': trimmed,
    'urlParts': uriParts(Uri.tryParse(trimmed)),
  });
  final error = _errorOf(answer);
  return error == null ? null : _urlErrorText(error);
}
