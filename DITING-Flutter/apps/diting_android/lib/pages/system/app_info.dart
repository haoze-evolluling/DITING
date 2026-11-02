/// App identity, external links and copy-to-clipboard shared by the about, update and
/// sponsor pages. The version comes from `pubspec.yaml` via `appVersionProvider`; links open in
/// the system handler and fall back to copying when nothing can handle the scheme.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Legacy `AboutScreen.PROJECT_REPOSITORY_URL`.
const projectRepositoryUrl = 'https://github.com/haoze-evolluling/DITING';

/// Legacy `SponsorScreen.SPONSOR_README_URL`.
const sponsorReadmeUrl = '$projectRepositoryUrl#sponsorship';

/// Upstream whose UI components were reused; credited on the about page.
const flClashRepositoryUrl = 'https://github.com/chen08209/FlClash';

/// Upstream the original Go tunnel kernel was forked from; credited on the about page.
const blockAdsRepositoryUrl =
    'https://github.com/pass-with-high-score/blockads-android';

/// Target group number of the legacy "join QQ group" action.
const qqGroupNumber = '1078502371';

/// Legacy `SettingsRouteActivity` opened `ACTION_VIEW` with this scheme to jump straight into the
/// group card, and told the user to search the number when QQ is not installed.
String get qqGroupUri =>
    'mqqapi://card/show_pslcard?src_type=internal&version=1'
    '&uin=$qqGroupNumber&card_type=group&source=qrcode';

/// Opens [url] with the system handler. False means no activity can handle the scheme (or the
/// platform channel is missing), which is what makes the caller copy the value instead.
Future<bool> openExternalLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}

/// Open [url], or copy it and show [fallbackMessage] when nothing can open it; a tap is never a
/// silent no-op either way.
Future<void> openLinkOrCopy(
  BuildContext context,
  String url,
  String fallbackMessage,
) async {
  if (await openExternalLink(url)) return;
  if (!context.mounted) return;
  await copyToClipboard(context, url, fallbackMessage);
}

/// Open the QQ group card; the group number is copied when QQ cannot handle the scheme, matching
/// the legacy "未检测到 QQ，请搜索群号" toast.
Future<void> joinQqGroup(BuildContext context) async {
  if (await openExternalLink(qqGroupUri)) return;
  if (!context.mounted) return;
  await copyToClipboard(
    context,
    qqGroupNumber,
    context.l10n.aboutQqCopied(qqGroupNumber),
  );
}

/// Copy [text] to the clipboard, then show [message]. The clipboard write is async
/// and the context may be gone afterwards, so `mounted` is re-checked each step.
Future<void> copyToClipboard(
  BuildContext context,
  String text,
  String message,
) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 2000),
    ),
  );
}
