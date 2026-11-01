/// The hub branch: the desktop console's resolution and protection pages, presented as the app's
/// grouped feature list instead of the mobile card board.
///
/// Only entries whose page exists are listed. A card that opens a placeholder would promise work
/// the host cannot do, and the migration order in `docs/development/flutter-desktop-ui.md` adds the
/// remaining rows as their data layers land.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/pages/hub/desktop_cache_page.dart';
import 'package:diting/desktop/pages/hub/desktop_dns64_page.dart';
import 'package:diting/desktop/pages/hub/desktop_encrypted_page.dart';
import 'package:diting/desktop/pages/hub/desktop_filter_config_page.dart';
import 'package:diting/desktop/pages/hub/desktop_filter_lists_page.dart';
import 'package:diting/desktop/pages/hub/desktop_filter_rules_page.dart';
import 'package:diting/desktop/pages/hub/desktop_schedule_page.dart';
import 'package:diting/desktop/pages/hub/desktop_privacy_page.dart';
import 'package:diting/desktop/pages/hub/desktop_services_page.dart';
import 'package:diting/desktop/pages/hub/desktop_rewrite_page.dart';
import 'package:diting/desktop/pages/hub/desktop_upstream_page.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Keeps a desktop feature list readable instead of stretching a row across a 1920-wide window.
const double _contentMaxWidth = 880;

class DesktopFeatureHubPage extends StatelessWidget {
  const DesktopFeatureHubPage({super.key});

  /// One feature row. The trailing chevron is the same on every row, so the builder owns it.
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
      title: l10n.bottomBarFeatureHub,
      body: PageBody(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListHeader(title: l10n.desktopHubResolveSection),
                    generateGroup([
                      _entry(
                        context,
                        glyph: AppGlyphs.dns,
                        title: l10n.desktopHubUpstream,
                        body: l10n.desktopHubUpstreamBody,
                        path: DesktopUpstreamPage.path,
                      ),
                      _entry(
                        context,
                        glyph: AppGlyphs.resources,
                        title: l10n.desktopHubCache,
                        body: l10n.desktopHubCacheBody,
                        path: DesktopCachePage.path,
                      ),
                      _entry(
                        context,
                        glyph: AppGlyphs.edit,
                        title: l10n.desktopHubRewrite,
                        body: l10n.desktopHubRewriteBody,
                        path: DesktopRewritePage.path,
                      ),
                      _entry(
                        context,
                        glyph: AppGlyphs.layers,
                        title: l10n.desktopHubDns64,
                        body: l10n.desktopHubDns64Body,
                        path: DesktopDns64Page.path,
                      ),
                    ]),
                    ListHeader(title: l10n.desktopHubProtectSection),
                    generateGroup([
                      _entry(
                        context,
                        glyph: AppGlyphs.rules,
                        title: l10n.desktopHubFilterLists,
                        body: l10n.desktopHubFilterListsBody,
                        path: DesktopFilterListsPage.path,
                      ),
                      _entry(
                        context,
                        glyph: AppGlyphs.edit,
                        title: l10n.desktopHubFilterRules,
                        body: l10n.desktopHubFilterRulesBody,
                        path: DesktopFilterRulesPage.path,
                      ),
                      _entry(
                        context,
                        glyph: AppGlyphs.sliders,
                        title: l10n.desktopHubFilterConfig,
                        body: l10n.desktopHubFilterConfigBody,
                        path: DesktopFilterConfigPage.path,
                      ),
                      _entry(
                        context,
                        glyph: AppGlyphs.clock,
                        title: l10n.desktopHubFilterSchedule,
                        body: l10n.desktopHubFilterScheduleBody,
                        path: DesktopSchedulePage.path,
                      ),
                      _entry(
                        context,
                        glyph: AppGlyphs.appsList,
                        title: l10n.desktopHubFilterServices,
                        body: l10n.desktopHubFilterServicesBody,
                        path: DesktopServicesPage.path,
                      ),
                    ]),
                    ListHeader(title: l10n.desktopHubDeviceSection),
                    generateGroup([
                      _entry(
                        context,
                        glyph: AppGlyphs.lock,
                        title: l10n.desktopHubEncrypted,
                        body: l10n.desktopHubEncryptedBody,
                        path: DesktopEncryptedPage.path,
                      ),
                      _entry(
                        context,
                        glyph: AppGlyphs.key,
                        title: l10n.desktopHubPrivacy,
                        body: l10n.desktopHubPrivacyBody,
                        path: DesktopPrivacyPage.path,
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
