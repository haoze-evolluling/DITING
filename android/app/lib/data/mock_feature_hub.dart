part of 'mock_data.dart';

/// One card; `description` is shared with the hidden-features page.
class MockFeatureCard {
  const MockFeatureCard({
    required this.title,
    required this.description,
    required this.glyphName,
    required this.route,
    this.featureKey,
    this.expressVisible = true,
    this.longPressRoute,
  });

  final String title;
  final String description;
  final String glyphName;
  final String route;

  /// Empty means the card is fixed.
  final String? featureKey;

  final bool expressVisible;

  final String? longPressRoute;

  bool get isFixed => featureKey == null;
}

class MockFeatureCategory {
  const MockFeatureCategory({required this.title, required this.cards});

  final String title;
  final List<MockFeatureCard> cards;
}

/// Routes are literals here; `test/route_catalog_test.dart` keeps them in sync.
///
/// Reading order is the module order the hub shows. Each category covers one kind of work so no
/// single page (previously 规则控制) has to host every new entry point:
/// edits the hub taxonomy in one place only.
List<MockFeatureCategory> mockFeatureCategories(AppL10n l10n) =>
    <MockFeatureCategory>[
  MockFeatureCategory(
    title: l10n.hubCategoryDns,
    cards: [
      MockFeatureCard(
        title: l10n.hubProviderManagement,
        description: l10n.hubProviderManagementDescription,
        glyphName: 'dns',
        route: '/hub/providers',
        featureKey: 'provider_management',
      ),
      MockFeatureCard(
        title: l10n.hubBootstrap,
        description: l10n.hubBootstrapDescription,
        glyphName: 'language',
        route: '/hub/bootstrap',
        featureKey: 'bootstrap_settings',
      ),
      MockFeatureCard(
        title: l10n.hubResolution,
        description: l10n.hubResolutionDescription,
        glyphName: 'shuffle',
        route: '/hub/resolution',
        featureKey: 'resolution_mode',
      ),
      MockFeatureCard(
        title: l10n.hubCache,
        description: l10n.hubCacheDescription,
        glyphName: 'memory',
        route: '/hub/cache',
        featureKey: 'cache_settings',
      ),
    ],
  ),
  MockFeatureCategory(
    title: l10n.hubCategoryRules,
    cards: [
      MockFeatureCard(
        title: l10n.hubRuleControl,
        description: l10n.hubRuleControlDescription,
        glyphName: 'rules',
        route: '/hub/rules',
        featureKey: 'rule_control',
      ),
      MockFeatureCard(
        title: l10n.hubBlocklist,
        description: l10n.hubBlocklistDescription,
        glyphName: 'block',
        route: '/rules/block',
        featureKey: 'blacklist',
      ),
      MockFeatureCard(
        title: l10n.hubAllowlist,
        description: l10n.hubAllowlistDescription,
        glyphName: 'verified',
        route: '/rules/allow',
        featureKey: 'whitelist',
      ),
      MockFeatureCard(
        title: l10n.hubRewrite,
        description: l10n.hubRewriteDescription,
        glyphName: 'swap',
        route: '/rules/rewrite',
        featureKey: 'rewrite_list',
        expressVisible: false,
      ),
    ],
  ),
  MockFeatureCategory(
    title: l10n.hubCategoryNetwork,
    cards: [
      MockFeatureCard(
        title: l10n.hubAppTraffic,
        description: l10n.hubAppTrafficDescription,
        glyphName: 'dataUsage',
        route: '/traffic',
        featureKey: 'traffic_stats',
        expressVisible: false,
      ),
      MockFeatureCard(
        title: l10n.hubAppRules,
        description: l10n.hubAppRulesDescription,
        glyphName: 'appsList',
        route: '/hub/app-rules',
        featureKey: 'app_rules',
        expressVisible: false,
      ),
      MockFeatureCard(
        title: l10n.hubBlockedApps,
        description: l10n.hubBlockedAppsDescription,
        glyphName: 'wifiOff',
        route: '/hub/blocked-apps',
        featureKey: 'blocked_apps',
        expressVisible: false,
      ),
      MockFeatureCard(
        title: l10n.hubExcludedApps,
        description: l10n.hubExcludedAppsDescription,
        glyphName: 'appsList',
        route: '/hub/excluded-apps',
        featureKey: 'excluded_apps',
        expressVisible: false,
      ),
    ],
  ),
  MockFeatureCategory(
    title: l10n.hubCategoryNetworkTools,
    cards: [
      MockFeatureCard(
        title: l10n.flowTitle,
        description: l10n.flowEntrySubtitle,
        glyphName: 'cloudSync',
        route: '/network/flow',
        featureKey: 'flow_view',
        expressVisible: false,
      ),
      MockFeatureCard(
        title: l10n.hubDnsLeak,
        description: l10n.networkDiagnosticsIntro,
        glyphName: 'speed',
        route: '/network/diagnostics',
        featureKey: 'network_diagnostics',
        expressVisible: false,
      ),
      MockFeatureCard(
        title: l10n.appInsightsTitle,
        description: l10n.appInsightsIntro,
        glyphName: 'dataUsage',
        route: '/network/insights',
        featureKey: 'app_insights',
        expressVisible: false,
      ),
      MockFeatureCard(
        title: l10n.privacySuiteTitle,
        description: l10n.privacySuiteIntro,
        glyphName: 'eyeOff',
        route: '/network/privacy',
        featureKey: 'privacy_suite',
      ),
      MockFeatureCard(
        title: l10n.dns64Title,
        description: l10n.dns64Intro,
        glyphName: 'link',
        route: '/network/dns64',
        featureKey: 'dns64',
      ),
      MockFeatureCard(
        title: l10n.devIpQuality,
        description: l10n.devIpQualityBody,
        glyphName: 'target',
        route: '/ip-quality',
        featureKey: 'ip_quality',
      ),
    ],
  ),
  MockFeatureCategory(
    title: l10n.hubCategoryAutomation,
    cards: [
      MockFeatureCard(
        title: l10n.automationTitle,
        description: l10n.automationSubtitle,
        glyphName: 'connections',
        route: '/automation',
        featureKey: 'automation',
      ),
      MockFeatureCard(
        title: l10n.profilesTitle,
        description: l10n.profilesSubtitle,
        glyphName: 'profiles',
        route: '/automation/profiles',
        featureKey: 'automation_profiles',
      ),
      MockFeatureCard(
        title: l10n.timetableTitle,
        description: l10n.timetableSubtitle,
        glyphName: 'clock',
        route: '/automation/timetable',
        featureKey: 'timetable',
      ),
      MockFeatureCard(
        title: l10n.netProfileTitle,
        description: l10n.netProfileSubtitle,
        glyphName: 'wifi',
        route: '/network/profiles',
        featureKey: 'network_profile',
      ),
    ],
  ),
  MockFeatureCategory(
    title: l10n.hubCategorySubscription,
    cards: [
      MockFeatureCard(
        title: l10n.ruleControlSubsTitle,
        description: l10n.ruleControlSubsSubtitle,
        glyphName: 'cloudSync',
        route: '/subscriptions',
        featureKey: 'subscriptions',
      ),
      MockFeatureCard(
        title: l10n.autoUpdateTitle,
        description: l10n.hubAutoUpdateDescription,
        glyphName: 'refresh',
        route: '/hub/rules/auto-update',
        featureKey: 'auto_update',
      ),
      MockFeatureCard(
        title: l10n.mirrorTplTitle,
        description: l10n.ruleControlMirrorSubtitle,
        glyphName: 'layers',
        route: '/hub/rules/mirrors',
        featureKey: 'mirror_templates',
      ),
    ],
  ),
  MockFeatureCategory(
    title: l10n.hubCategoryIntegration,
    cards: [
      MockFeatureCard(
        title: l10n.localApiTitle,
        description: l10n.localApiIntro,
        glyphName: 'key',
        route: '/network/local-api',
        featureKey: 'local_api',
      ),
      MockFeatureCard(
        title: l10n.webhookTitle,
        description: l10n.webhookIntro,
        glyphName: 'send',
        route: '/hub/rules/webhook',
        featureKey: 'webhook',
      ),
      MockFeatureCard(
        title: l10n.lanRateLimitTitle,
        description: l10n.lanRateLimitIntro,
        glyphName: 'speed',
        route: '/network/lan-rate-limit',
        featureKey: 'lan_rate_limit',
      ),
      MockFeatureCard(
        title: l10n.customResourcesTitle,
        description: l10n.devCustomResourcesBody,
        glyphName: 'resources',
        route: '/config/custom-resources',
        featureKey: 'custom_resources',
      ),
    ],
  ),
  MockFeatureCategory(
    title: l10n.hubCategoryAdvanced,
    cards: [
      MockFeatureCard(
        title: l10n.hubHttpsInspection,
        description: l10n.hubHttpsInspectionDescription,
        glyphName: 'target',
        route: '/hub/https-inspection',
        featureKey: 'https_inspection',
        expressVisible: false,
      ),
      MockFeatureCard(
        title: l10n.hubOutboundProxy,
        description: l10n.hubOutboundProxyDescription,
        glyphName: 'link',
        route: '/hub/outbound-proxy',
        featureKey: 'outbound_proxy',
        expressVisible: false,
      ),
      MockFeatureCard(
        title: l10n.hubDiagnostics,
        description: l10n.hubDiagnosticsDescription,
        glyphName: 'speed',
        route: '/tools',
        featureKey: 'network_tools',
        expressVisible: false,
      ),
      MockFeatureCard(
        title: l10n.hubAiAnalysis,
        description: l10n.hubAiAnalysisDescription,
        glyphName: 'sparkle',
        route: '/hub/agent',
        featureKey: 'agent_api',
        expressVisible: false,
      ),
    ],
  ),
  MockFeatureCategory(
    title: l10n.hubCategoryInterface,
    cards: [
      MockFeatureCard(
        title: l10n.hubAppearance,
        description: l10n.hubAppearanceDescription,
        glyphName: 'palette',
        route: '/theme',
        featureKey: 'appearance',
      ),
      MockFeatureCard(
        title: l10n.hubProviderVisibility,
        description: l10n.hubProviderVisibilityDescription,
        glyphName: 'eye',
        route: '/hub/provider-visibility',
        featureKey: 'service_display',
      ),
      MockFeatureCard(
        title: l10n.hubHiddenFeatures,
        description: l10n.hubHiddenFeaturesDescription,
        glyphName: 'eyeOff',
        route: '/hub/hidden-features',
      ),
      MockFeatureCard(
        title: l10n.hubOtherSettings,
        description: l10n.hubOtherSettingsDescription,
        glyphName: 'settings',
        route: '/settings',
        featureKey: 'other_settings',
      ),
    ],
  ),
  MockFeatureCategory(
    title: l10n.hubCategoryData,
    cards: [
      MockFeatureCard(
        title: l10n.hubLogs,
        description: l10n.hubLogsDescription,
        glyphName: 'logs',
        route: '/logs',
        featureKey: 'logs',
        longPressRoute: '/hub/log-retention',
      ),
      MockFeatureCard(
        title: l10n.devRequestLogs,
        description: l10n.devRequestLogsBody,
        glyphName: 'requests',
        route: '/requests',
        featureKey: 'request_logs',
      ),
      MockFeatureCard(
        title: l10n.hubBackup,
        description: l10n.hubBackupDescription,
        glyphName: 'export',
        route: '/hub/config-transfer',
        featureKey: 'data_management',
      ),
      MockFeatureCard(
        title: l10n.hubDataCleanup,
        description: l10n.hubDataCleanupDescription,
        glyphName: 'broom',
        route: '/hub/data-cleanup',
        featureKey: 'data_cleanup',
      ),
      MockFeatureCard(
        title: l10n.hubTroubleshooting,
        description: l10n.hubTroubleshootingDescription,
        glyphName: 'wrench',
        route: '/hub/troubleshooting',
        featureKey: 'troubleshooting',
      ),
    ],
  ),
  MockFeatureCategory(
    title: l10n.hubCategoryAbout,
    cards: [
      MockFeatureCard(
        title: l10n.hubAbout,
        description: l10n.hubAboutDescription,
        glyphName: 'info',
        route: '/about',
        featureKey: 'app_info',
      ),
      MockFeatureCard(
        title: l10n.hubSponsor,
        description: l10n.hubSponsorDescription,
        glyphName: 'star',
        route: '/sponsor',
        featureKey: 'sponsor',
      ),
      MockFeatureCard(
        title: l10n.hubSponsors,
        description: l10n.hubSponsorsDescription,
        glyphName: 'verified',
        route: '/hub/sponsor-list',
        featureKey: 'sponsor_list',
      ),
      MockFeatureCard(
        title: l10n.hubContributors,
        description: l10n.hubContributorsDescription,
        glyphName: 'account',
        route: '/hub/co-builders',
        featureKey: 'contributors',
      ),
    ],
  ),
];

class MockHiddenFeature {
  const MockHiddenFeature({
    required this.key,
    required this.title,
    required this.description,
    required this.glyphName,
    required this.category,
    required this.expressVisible,
    required this.route,
  });

  final String key;
  final String title;
  final String description;
  final String glyphName;
  final String category;
  final bool expressVisible;
  final String route;
}

List<MockHiddenFeature> mockHiddenFeatures(AppL10n l10n) => [
  for (final category in mockFeatureCategories(l10n))
    for (final card in category.cards)
      if (card.featureKey case final key?)
        MockHiddenFeature(
          key: key,
          title: card.title,
          description: card.description,
          glyphName: card.glyphName,
          category: category.title,
          expressVisible: card.expressVisible,
          route: card.route,
        ),
];

Map<String, List<MockHiddenFeature>> hiddenFeaturesByCategory({
  required bool express,
  required AppL10n l10n,
}) {
  final result = <String, List<MockHiddenFeature>>{};
  for (final feature in mockHiddenFeatures(l10n)) {
    if (express && !feature.expressVisible) {
      continue;
    }
    result.putIfAbsent(feature.category, () => []).add(feature);
  }
  return result;
}

List<MockFeatureCategory> visibleFeatureCategories({
  required bool express,
  required Set<String> hiddenKeys,
  required AppL10n l10n,
}) {
  final result = <MockFeatureCategory>[];
  for (final category in mockFeatureCategories(l10n)) {
    final cards = [
      for (final card in category.cards)
        if ((!express || card.expressVisible) &&
            (card.isFixed || !hiddenKeys.contains(card.featureKey)))
          card,
    ];
    if (cards.isNotEmpty) {
      result.add(MockFeatureCategory(title: category.title, cards: cards));
    }
  }
  return result;
}
