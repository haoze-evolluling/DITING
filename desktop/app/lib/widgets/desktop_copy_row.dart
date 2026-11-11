/// One copyable value row: the old console's `CopyRow`, drawn with the shared card pieces.
///
/// The LAN DNS page lists several addresses to paste into a router or a phone, so the copy affordance
/// is a row of its own rather than a button per card. Kept here so the two pages that need it cannot
/// drift into two different shapes.
library;

import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class DesktopCopyRow extends StatelessWidget {
  const DesktopCopyRow({super.key, required this.value, this.tag});

  final String value;

  /// A short kind label, e.g. `IPv4` or `IPv6`; omitted when the value speaks for itself.
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final tag = this.tag;
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(context).toTabular,
            ),
          ),
          if (tag != null)
            Text(tag, style: DashboardText.label(context)),
          SizedBox(
            height: 28,
            child: DashboardIconButton(
              glyph: AppGlyphs.copy,
              tooltip: MaterialLocalizations.of(context).copyButtonLabel,
              size: 28,
              glyphSize: 15,
              onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            ),
          ),
        ],
      ),
    );
  }
}
