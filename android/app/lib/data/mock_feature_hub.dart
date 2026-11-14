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
/// Reading order is the module order the hub shows. The hub is the single entry point for the
/// most-used modules (currently 24 cards in 6 categories, 4 per category so every two-column row
/// stays full and every mode has an even count per category). Low-frequency functions are folded
/// into a parent page's secondary entries instead of taking a card of their own:
///   - 服务商管理 → 引导解析 / 服务显示
///   - 规则控制 → 域名黑名单 / 域名白名单 / 域名覆写
///   - 规则订阅 → 自动更新 / 镜像模板
///   - 自动化 → 配置档案 / 分时规则 / 网络档案
///   - 应用规则 → 断网应用 / 直连应用
///   - 数据与维护 → 数据清理 / 故障排查
///   - 关于 → 赞助
///   - 日志/流量/设置/请求日志/镜像模板 仍可从对应底栏 Tab 或既有页面进入。
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
      MockFeatureCard(
        title: l10n.dns64Title,
        description: l10n.dns64Intro,
        glyphName: 'link',
        route: '/network/dns64',
        featureKey: 'dns64',
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
        title: l10n.ruleControlSubsTitle,
        description: l10n.ruleControlSubsSubtitle,
        glyphName: 'cloudSync',
        route: '/subscriptions',
        featureKey: 'subscriptions',
      ),
      MockFeatureCard(
        title: l10n.privacySuiteTitle,
        description: l10n.privacySuiteIntro,
        glyphName: 'eyeOff',
        route: '/network/privacy',
        featureKey: 'privacy_suite',
      ),
      MockFeatureCard(
        title: l10n.automationTitle,
        description: l10n.automationSubtitle,
        glyphName: 'connections',
        route: '/automation',
        featureKey: 'automation',
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
        title: l10n.hubHiddenFeatures,
        description: l10n.hubHiddenFeaturesDescription,
        glyphName: 'eyeOff',
        route: '/hub/hidden-features',
      ),
      MockFeatureCard(
        title: l10n.hubBackup,
        description: l10n.hubBackupDescription,
        glyphName: 'export',
        route: '/hub/config-transfer',
        featureKey: 'data_management',
      ),
      MockFeatureCard(
        title: l10n.hubAbout,
        description: l10n.hubAboutDescription,
        glyphName: 'info',
        route: '/about',
        featureKey: 'app_info',
      ),
    ],
  ),
  MockFeatureCategory(
    title: l10n.hubCategoryNetwork,
    cards: [
      MockFeatureCard(
        title: l10n.hubAppRules,
        description: l10n.hubAppRulesDescription,
        glyphName: 'appsList',
        route: '/hub/app-rules',
        featureKey: 'app_rules',
        expressVisible: false,
      ),
      MockFeatureCard(
        title: l10n.flowTitle,
        description: l10n.flowEntrySubtitle,
        glyphName: 'cloudSync',
        route: '/network/flow',
        featureKey: 'flow_view',
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
        title: l10n.hubDnsLeak,
        description: l10n.networkDiagnosticsIntro,
        glyphName: 'speed',
        route: '/network/diagnostics',
        featureKey: 'network_diagnostics',
        expressVisible: false,
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
        title: l10n.hubAiAnalysis,
        description: l10n.hubAiAnalysisDescription,
        glyphName: 'sparkle',
        route: '/hub/agent',
        featureKey: 'agent_api',
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
