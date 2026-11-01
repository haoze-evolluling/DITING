/// The settings branch's appearance page: the palette and the day/night mode.
///
/// The old desktop console's `AppearancePanel.vue` is the functional blueprint. It writes the same
/// appearance keys the Android pages write, so a choice made here survives a restart and shows up
/// everywhere.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/pages/settings/widgets/appearance_theme_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:material_ui/material_ui.dart';

const double _contentMaxWidth = 980;

class DesktopAppearancePage extends StatelessWidget {
  const DesktopAppearancePage({super.key});

  static const path = '/settings/appearance';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CommonScaffold(
      title: l10n.desktopSettingsAppearance,
      body: PageBody(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: dashboardCardGap,
                  children: const [AppearanceThemeCard()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
