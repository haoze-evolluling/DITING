/// Small, shared pieces of the rewrite page: the type chip labels and their tones, the lifetime a
/// row falls back to, and the "answer" line a rule row prints. Nothing here decides rewrite state;
/// the service does.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_rewrite_models.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:material_ui/material_ui.dart';

/// `A / AAAA` is the shortcut address fields; every other chip is the record type as the service
/// names it, so the two lists cannot drift.
String desktopRewriteTypeLabel(BuildContext context, String type) =>
    type == desktopRewriteAddressChip
    ? context.l10n.desktopRewriteTypeIp
    : type;

/// A failure response code is the only warning; an address chip is the only "good" one. Alias and
/// text rules are neutral, exactly like the console's own badge colours.
DashboardChipTone desktopRewriteTypeTone(String type) {
  if (type == desktopRewriteAddressChip) return DashboardChipTone.ok;
  if (desktopRewriteRcodes.contains(type) && type != 'NOERROR') {
    return DashboardChipTone.warn;
  }
  return DashboardChipTone.idle;
}

/// The row's own lifetime, or the engine's default when the rule left it at zero.
int desktopRewriteRuleTtl(
  DesktopRewriteRule rule,
  DesktopRewriteConfig config,
) => rule.ttl > 0 ? rule.ttl : config.effectiveTtl;
