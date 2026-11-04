/// The hub's appearance page: the palette and the day/night mode.
///
/// The old desktop console's `AppearancePanel.vue` is the functional blueprint. It writes the same
/// appearance keys the Android pages write, so a choice made here survives a restart and shows up
/// everywhere.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/pages/settings/widgets/appearance_theme_card.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:material_ui/material_ui.dart';

class DesktopAppearancePage extends StatelessWidget {
  const DesktopAppearancePage({super.key});

  static const path = '/hub/appearance';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CommonScaffold(
      title: l10n.desktopSettingsAppearance,
      body: const PageBody(
        children: [
          DesktopCardBoard(cards: [AppearanceThemeCard()], singleColumn: true),
        ],
      ),
    );
  }
}
