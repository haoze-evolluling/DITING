/// The settings branch: appearance, the service connection and the LAN console, as a desktop list.
///
/// Only entries whose page exists are listed, for the same reason as the hub: a row that opens a
/// placeholder would promise work the host cannot do. The migration order in
/// `docs/development/flutter-desktop-ui.md` adds the remaining rows as their data layers land.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_auth_providers.dart';
import 'package:diting_desktop/pages/settings/desktop_appearance_page.dart';
import 'package:diting_desktop/pages/settings/desktop_lan_web_page.dart';
import 'package:diting_desktop/pages/settings/desktop_service_page.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class DesktopSettingsPage extends ConsumerWidget {
  const DesktopSettingsPage({super.key});

  /// The browser session is the only thing this branch can end; the desktop window has none.
  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await confirmDesktopAction(
      context,
      title: l10n.desktopSettingsLogout,
      body: l10n.desktopSettingsLogoutConfirm,
      confirmLabel: l10n.desktopSettingsLogout,
    );
    if (!confirmed || !context.mounted) return;
    final error = await ref.read(desktopAuthProvider.notifier).signOut();
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null ? l10n.desktopSettingsLogoutDone : error.message,
    );
  }

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
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final webConsole = ref.watch(desktopWebConsoleProvider);
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
              if (webConsole)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListHeader(title: l10n.desktopSettingsSessionSection),
                    generateGroup([
                      ListItem(
                        leading: const GlyphIcon(AppGlyphs.lock, size: 20),
                        title: Text(l10n.desktopSettingsLogout),
                        subtitle: Text(l10n.desktopSettingsLogoutBody),
                        trailing: const GlyphIcon(
                          AppGlyphs.chevronForward,
                          size: 18,
                        ),
                        onTap: () => _signOut(context, ref),
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
