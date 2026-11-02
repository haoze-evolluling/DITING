/// App identity and external links for the desktop about page. Same targets as the Android about
/// page (the repository, its sponsorship section, the two credited upstreams and the QQ group), so
/// both hosts open the same places.
///
/// Opening is best-effort: the desktop window and the LAN console are the same bundle, and a host
/// without a URL handler is a normal case, not an error. When nothing opens, the address is copied
/// and the reader is told, so a tap is never a silent no-op.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
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
/// group card.
String get qqGroupUri =>
    'mqqapi://card/show_pslcard?src_type=internal&version=1'
    '&uin=$qqGroupNumber&card_type=group&source=qrcode';

/// Whether the host handed the URL to something outside the app. A missing handler, a missing
/// plugin and an unparsable scheme all mean "no", and the caller copies instead.
Future<bool> _openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Opens [url] with the system handler; copies it and says so when nothing can open it.
Future<void> openDesktopLink(BuildContext context, String url) async {
  if (await _openExternal(url)) return;
  if (!context.mounted) return;
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  showDesktopMessage(context, context.l10n.aboutLinkCopyFallback(url));
}

/// Joins the QQ group card, falling back to copying the group number when QQ cannot handle it.
Future<void> openDesktopQqGroup(BuildContext context) async {
  if (await _openExternal(qqGroupUri)) return;
  if (!context.mounted) return;
  await Clipboard.setData(const ClipboardData(text: qqGroupNumber));
  if (!context.mounted) return;
  showDesktopMessage(context, context.l10n.aboutQqCopied(qqGroupNumber));
}
