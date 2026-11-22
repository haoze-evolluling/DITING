library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/widgets/app_snack.dart';
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

Future<void> openLinkOrCopy(
  BuildContext context,
  String url,
  String fallbackMessage,
) async {
  if (await openExternalLink(url)) return;
  if (!context.mounted) return;
  await copyToClipboard(context, url, fallbackMessage);
}

Future<void> joinQqGroup(BuildContext context) async {
  if (await openExternalLink(qqGroupUri)) return;
  if (!context.mounted) return;
  await copyToClipboard(
    context,
    qqGroupNumber,
    context.l10n.aboutQqCopied(qqGroupNumber),
  );
}

Future<void> copyToClipboard(
  BuildContext context,
  String text,
  String message,
) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  showAppSnack(context, message, duration: const Duration(milliseconds: 2000));
}
