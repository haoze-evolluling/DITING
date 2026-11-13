/// Fallback page for unmatched routes.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class UnknownRoutePage extends StatelessWidget {
  const UnknownRoutePage({super.key, required this.location});

  /// The address the user actually opened, shown so both users and developers can
  /// report or locate it.
  final String location;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonScaffold(
      title: context.l10n.unknownRouteTitle,
      // The body starts at y=0 under the floating app bar, so a centered column would
      // slide under it on narrow screens or large text; `AppBarClearance` reserves room.
      body: AppBarClearance(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 12,
              children: [
                GlyphIcon(
                  AppGlyphs.search,
                  size: 40,
                  color: colorScheme.onSurfaceVariant,
                ),
                Text(
                  context.l10n.unknownRouteBody,
                  textAlign: TextAlign.center,
                  style: AppTextStyle.title3.of(context, emphasized: true),
                ),
                SelectableText(
                  location,
                  textAlign: TextAlign.center,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                TonalButton(
                  label: context.l10n.unknownRouteBack,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
