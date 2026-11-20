library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_rewrite_models.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:material_ui/material_ui.dart';

String desktopRewriteTypeLabel(BuildContext context, String type) =>
    type == desktopRewriteAddressChip
    ? context.l10n.desktopRewriteTypeIp
    : type;

DashboardChipTone desktopRewriteTypeTone(String type) {
  if (type == desktopRewriteAddressChip) return DashboardChipTone.ok;
  if (desktopRewriteRcodes.contains(type) && type != 'NOERROR') {
    return DashboardChipTone.warn;
  }
  return DashboardChipTone.idle;
}

int desktopRewriteRuleTtl(
  DesktopRewriteRule rule,
  DesktopRewriteConfig config,
) => rule.ttl > 0 ? rule.ttl : config.effectiveTtl;
