library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_tools_providers.dart';
import 'package:diting_desktop/pages/hub/desktop_adapters_page.dart';
import 'package:diting_desktop/pages/hub/desktop_cache_page.dart';
import 'package:diting_desktop/pages/hub/desktop_client_access_page.dart';
import 'package:diting_desktop/pages/hub/desktop_dns64_page.dart';
import 'package:diting_desktop/pages/hub/desktop_encrypted_page.dart';
import 'package:diting_desktop/pages/hub/desktop_filter_config_page.dart';
import 'package:diting_desktop/pages/hub/desktop_filter_lists_page.dart';
import 'package:diting_desktop/pages/hub/desktop_filter_rules_page.dart';
import 'package:diting_desktop/pages/hub/desktop_lan_dns_page.dart';
import 'package:diting_desktop/pages/hub/desktop_schedule_page.dart';
import 'package:diting_desktop/pages/hub/desktop_privacy_page.dart';
import 'package:diting_desktop/pages/hub/desktop_query_log_page.dart';
import 'package:diting_desktop/pages/hub/desktop_services_page.dart';
import 'package:diting_desktop/pages/hub/desktop_rewrite_page.dart';
import 'package:diting_desktop/pages/hub/desktop_upstream_page.dart';
import 'package:diting_desktop/pages/settings/desktop_appearance_page.dart';
import 'package:diting_desktop/pages/settings/desktop_lan_web_page.dart';
import 'package:diting_desktop/pages/settings/desktop_service_page.dart';
import 'package:diting_desktop/pages/tools/desktop_rule_check_page.dart';
import 'package:diting_desktop/pages/tools/widgets/emergency_restore_card.dart';
import 'package:diting_desktop/pages/tools/widgets/port_diagnosis_card.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class DesktopFeatureHubPage extends ConsumerWidget {
  const DesktopFeatureHubPage({super.key});

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

  Widget _category({
    required String title,
    required List<Widget> entries,
    List<Widget> cards = const [],
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListHeader(title: title),
      generateGroup(entries),
      for (final card in cards)
        Padding(
          padding: const EdgeInsets.only(top: dashboardCardGap),
          child: card,
        ),
    ],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final portCheck = ref.watch(desktopPortCheckProvider);
    return CommonScaffold(
      title: l10n.bottomBarFeatureHub,
      body: PageBody(
        children: [
          DesktopCardBoard(
            cards: [
              _category(
                title: l10n.desktopHubResolveSection,
                entries: [
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
                ],
              ),
              _category(
                title: l10n.desktopHubProtectSection,
                entries: [
                  _entry(
                    context,
                    glyph: AppGlyphs.appsList,
                    title: l10n.desktopHubFilterServices,
                    body: l10n.desktopHubFilterServicesBody,
                    path: DesktopServicesPage.path,
                  ),
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
                ],
              ),
              _category(
                title: l10n.desktopHubPrivacySection,
                entries: [
                  _entry(
                    context,
                    glyph: AppGlyphs.key,
                    title: l10n.desktopHubPrivacy,
                    body: l10n.desktopHubPrivacyBody,
                    path: DesktopPrivacyPage.path,
                  ),
                  _entry(
                    context,
                    glyph: AppGlyphs.lock,
                    title: l10n.desktopHubEncrypted,
                    body: l10n.desktopHubEncryptedBody,
                    path: DesktopEncryptedPage.path,
                  ),
                ],
              ),
              _category(
                title: l10n.desktopHubShareSection,
                entries: [
                  _entry(
                    context,
                    glyph: AppGlyphs.connections,
                    title: l10n.desktopHubAdapters,
                    body: l10n.desktopHubAdaptersBody,
                    path: DesktopAdaptersPage.path,
                  ),
                  _entry(
                    context,
                    glyph: AppGlyphs.dns,
                    title: l10n.desktopHubLanDns,
                    body: l10n.desktopHubLanDnsBody,
                    path: DesktopLanDnsPage.path,
                  ),
                  _entry(
                    context,
                    glyph: AppGlyphs.link,
                    title: l10n.desktopLanWebPageTitle,
                    body: l10n.desktopLanWebEntryBody,
                    path: DesktopLanWebPage.path,
                  ),
                  _entry(
                    context,
                    glyph: AppGlyphs.devices,
                    title: l10n.desktopHubClientAccess,
                    body: l10n.desktopHubClientAccessBody,
                    path: DesktopClientAccessPage.path,
                  ),
                ],
              ),
              _category(
                title: l10n.desktopHubDiagnoseSection,
                entries: [
                  _entry(
                    context,
                    glyph: AppGlyphs.rules,
                    title: l10n.desktopToolsRulePageTitle,
                    body: l10n.desktopToolsRuleEntryBody,
                    path: DesktopRuleCheckPage.path,
                  ),
                  _entry(
                    context,
                    glyph: AppGlyphs.logs,
                    title: l10n.desktopHubQueryLog,
                    body: l10n.desktopHubQueryLogBody,
                    path: DesktopQueryLogPage.path,
                  ),
                ],
                cards: [
                  PortDiagnosisCard(state: portCheck),
                  const EmergencyRestoreCard(),
                ],
              ),
              _category(
                title: l10n.desktopHubAppSection,
                entries: [
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
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
