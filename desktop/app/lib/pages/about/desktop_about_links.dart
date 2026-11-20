library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

const projectRepositoryUrl = 'https://github.com/haoze-evolluling/DITING';

const sponsorReadmeUrl = '$projectRepositoryUrl#sponsorship';

const flClashRepositoryUrl = 'https://github.com/chen08209/FlClash';

const blockAdsRepositoryUrl =
    'https://github.com/pass-with-high-score/blockads-android';

const qqGroupNumber = '1078502371';

String get qqGroupUri =>
    'mqqapi://card/show_pslcard?src_type=internal&version=1'
    '&uin=$qqGroupNumber&card_type=group&source=qrcode';

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

Future<void> openDesktopLink(BuildContext context, String url) async {
  if (await _openExternal(url)) return;
  if (!context.mounted) return;
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  showDesktopMessage(context, context.l10n.aboutLinkCopyFallback(url));
}

Future<void> openDesktopQqGroup(BuildContext context) async {
  if (await _openExternal(qqGroupUri)) return;
  if (!context.mounted) return;
  await Clipboard.setData(const ClipboardData(text: qqGroupNumber));
  if (!context.mounted) return;
  showDesktopMessage(context, context.l10n.aboutQqCopied(qqGroupNumber));
}
