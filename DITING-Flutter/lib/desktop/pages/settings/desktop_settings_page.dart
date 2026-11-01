/// The settings branch: appearance, the service connection and the LAN console, as a desktop list.
///
/// Only entries whose page exists are listed, for the same reason as the hub: a row that opens a
/// placeholder would promise work the host cannot do. The migration order in
/// `docs/development/flutter-desktop-ui.md` adds the remaining rows as their data layers land.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/pages/settings/desktop_appearance_page.dart';
import 'package:diting/desktop/pages/settings/desktop_lan_web_page.dart';
import 'package:diting/desktop/pages/settings/desktop_service_page.dart';
import 'package:diting/desktop/widgets/desktop_card_board.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class DesktopSettingsPage extends StatelessWidget {
  const DesktopSettingsPage({super.key});

  ListItem _entry(
    BuildContext context, {
    required Glyph glyph,
    required String title,
    required String body,
    required String path,
  }) => ListItem(
    leading: GlyphIcon(glyph, size: 20),
    title: Text(title),
    subtitle: Text(body),
    trailing: const GlyphIcon(AppGlyphs.chevronForward, size: 18),
    onTap: () => context.push(path),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CommonScaffold(
      title: l10n.bottomBarSettings,
      body: PageBody(
        children: [
          DesktopCardBoard(
            cards: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListHeader(title: l10n.desktopSettingsSection),
                  generateGroup([
                    _entry(
                      context,
                      glyph: AppGlyphs.palette,
                      title: l10n.desktopSettingsAppearance,
                      body: l10n.desktopSettingsAppearanceEntryBody,
                      path: DesktopAppearancePage.path,
                    ),
                    _entry(
                      context,
                      glyph: AppGlyphs.sync,
                      title: l10n.desktopServicePageTitle,
                      body: l10n.desktopServiceEntryBody,
                      path: DesktopServicePage.path,
                    ),
                    _entry(
                      context,
                      glyph: AppGlyphs.link,
                      title: l10n.desktopLanWebPageTitle,
                      body: l10n.desktopLanWebEntryBody,
                      path: DesktopLanWebPage.path,
                    ),
                  ]),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
