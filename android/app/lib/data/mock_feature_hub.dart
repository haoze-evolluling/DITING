part of 'mock_data.dart';

class MockFeatureCard {
  const MockFeatureCard({
    required this.title,
    required this.description,
    required this.glyphName,
    required this.route,
    this.featureKey,
    this.longPressRoute,
  });

  final String title;
  final String description;
  final String glyphName;
  final String route;

  final String? featureKey;

  final String? longPressRoute;

  bool get isFixed => featureKey == null;
}

/// 功能中心分类的稳定标识。
///
/// 卡片与分类标题随语言变化，按标题判断分类并不可靠；简洁模式的默认隐藏
/// 规则与升级迁移一律用这里的 [id] 判断。
enum FeatureCategoryId { dns, rules, network, advanced, data, interface_ }

class MockFeatureCategory {
  const MockFeatureCategory({
    required this.id,
    required this.title,
    required this.cards,
  });

  final FeatureCategoryId id;
  final String title;
  final List<MockFeatureCard> cards;
}

List<MockFeatureCategory> mockFeatureCategories(AppL10n l10n) =>
    <MockFeatureCategory>[
      MockFeatureCategory(
        id: FeatureCategoryId.dns,
        title: l10n.hubCategoryDns,
        cards: [
          MockFeatureCard(
            title: l10n.hubProviderManagement,
            description: l10n.hubProviderManagementDescription,
            glyphName: 'upstream',
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
            title: l10n.hubProviderVisibility,
            description: l10n.hubProviderVisibilityDescription,
            glyphName: 'eye',
            route: '/hub/provider-visibility',
            featureKey: 'service_display',
          ),
        ],
      ),
      MockFeatureCategory(
        id: FeatureCategoryId.rules,
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
            title: l10n.hubAppRules,
            description: l10n.hubAppRulesDescription,
            glyphName: 'appsList',
            route: '/hub/app-rules',
            featureKey: 'app_rules',
          ),
          MockFeatureCard(
            title: l10n.privacySuiteTitle,
            description: l10n.privacySuiteIntro,
            glyphName: 'eyeOff',
            route: '/network/privacy',
            featureKey: 'privacy_suite',
          ),
        ],
      ),
      MockFeatureCategory(
        id: FeatureCategoryId.network,
        title: l10n.hubCategoryNetwork,
        cards: [
          MockFeatureCard(
            title: l10n.flowTitle,
            description: l10n.appInsightsIntro,
            glyphName: 'connections',
            route: '/network/flow',
            featureKey: 'flow_view',
          ),
          MockFeatureCard(
            title: l10n.hubAppTraffic,
            description: l10n.hubAppTrafficDescription,
            glyphName: 'dataUsage',
            route: '/traffic',
            featureKey: 'traffic_stats',
          ),
          MockFeatureCard(
            title: l10n.bottomBarNetworkTools,
            description: l10n.hubDiagnosticsDescription,
            glyphName: 'tools',
            route: '/tools',
            featureKey: 'network_tools',
          ),
          MockFeatureCard(
            title: l10n.connectionRateLimitTitle,
            description: l10n.connectionRateLimitCardDescription,
            glyphName: 'speed',
            route: '/network/connection-rate-limit',
            featureKey: 'connection_rate_limit',
          ),
        ],
      ),
      MockFeatureCategory(
        id: FeatureCategoryId.advanced,
        title: l10n.hubCategoryAdvanced,
        cards: [
          MockFeatureCard(
            title: l10n.hubDiagnostics,
            description: l10n.networkDiagnosticsIntro,
            glyphName: 'target',
            route: '/network/diagnostics',
            featureKey: 'network_diagnostics',
          ),
          MockFeatureCard(
            title: l10n.hubAiAnalysis,
            description: l10n.hubAiAnalysisDescription,
            glyphName: 'sparkle',
            route: '/hub/agent',
            featureKey: 'agent_api',
          ),
          MockFeatureCard(
            title: l10n.hubHttpsInspection,
            description: l10n.hubHttpsInspectionDescription,
            glyphName: 'lock',
            route: '/hub/https-inspection',
            featureKey: 'https_inspection',
          ),
          MockFeatureCard(
            title: l10n.hubOutboundProxy,
            description: l10n.hubOutboundProxyDescription,
            glyphName: 'link',
            route: '/hub/outbound-proxy',
            featureKey: 'outbound_proxy',
          ),
        ],
      ),
      MockFeatureCategory(
        id: FeatureCategoryId.data,
        title: l10n.hubCategoryData,
        cards: [
          MockFeatureCard(
            title: l10n.transferTitle,
            description: l10n.hubBackupDescription,
            glyphName: 'export',
            route: '/hub/config-transfer',
            featureKey: 'data_management',
          ),
          MockFeatureCard(
            title: l10n.logRetentionTitle,
            description: l10n.settingsLogModeSubtitle,
            glyphName: 'calendar',
            route: '/hub/log-retention',
            featureKey: 'log_retention',
          ),
          MockFeatureCard(
            title: l10n.bottomBarLogDashboard,
            description: l10n.hubLogsDescription,
            glyphName: 'logs',
            route: '/logs',
            featureKey: 'logs',
          ),
          MockFeatureCard(
            title: l10n.hubTroubleshooting,
            description: l10n.hubTroubleshootingDescription,
            glyphName: 'stethoscope',
            route: '/hub/troubleshooting',
            featureKey: 'troubleshooting',
          ),
          MockFeatureCard(
            title: l10n.hubDataCleanup,
            description: l10n.hubDataCleanupDescription,
            glyphName: 'broom',
            route: '/hub/data-cleanup',
            featureKey: 'data_cleanup',
          ),
          MockFeatureCard(
            title: l10n.foregroundTitle,
            description: l10n.settingsForegroundSubtitle,
            glyphName: 'eyeOff',
            route: '/settings/background',
            featureKey: 'foreground_behavior',
          ),
        ],
      ),
      MockFeatureCategory(
        id: FeatureCategoryId.interface_,
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
            title: l10n.hubOtherSettings,
            description: l10n.hubOtherSettingsDescription,
            glyphName: 'settings',
            route: '/settings',
            featureKey: 'other_settings',
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
    ];

class MockHiddenFeature {
  const MockHiddenFeature({
    required this.key,
    required this.title,
    required this.description,
    required this.glyphName,
    required this.category,
    required this.route,
  });

  final String key;
  final String title;
  final String description;
  final String glyphName;
  final String category;
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
          route: card.route,
        ),
];

Map<String, List<MockHiddenFeature>> hiddenFeaturesByCategory({
  required AppL10n l10n,
}) {
  final result = <String, List<MockHiddenFeature>>{};
  for (final feature in mockHiddenFeatures(l10n)) {
    result.putIfAbsent(feature.category, () => []).add(feature);
  }
  return result;
}

List<MockFeatureCategory> visibleFeatureCategories({
  required Set<String> hiddenKeys,
  required AppL10n l10n,
}) {
  final result = <MockFeatureCategory>[];
  for (final category in mockFeatureCategories(l10n)) {
    final cards = [
      for (final card in category.cards)
        if (card.isFixed || !hiddenKeys.contains(card.featureKey)) card,
    ];
    if (cards.isNotEmpty) {
      result.add(
        MockFeatureCategory(
          id: category.id,
          title: category.title,
          cards: cards,
        ),
      );
    }
  }
  return result;
}

/// 简洁模式默认收进「隐藏功能」的分类：应用与网络、高级与诊断、数据与维护。
const simpleModeHiddenCategoryIds = <FeatureCategoryId>{
  FeatureCategoryId.network,
  FeatureCategoryId.advanced,
  FeatureCategoryId.data,
};

/// 给定分类下所有卡片的隐藏键。
///
/// 隐藏键与语言无关，因此这里只借用 [l10n] 构造分类清单：任何语言的同一分类
/// 得到的键集合都相同。
Set<String> hiddenKeysOfCategories(
  Set<FeatureCategoryId> categoryIds, {
  required AppL10n l10n,
}) => {
  for (final category in mockFeatureCategories(l10n))
    if (categoryIds.contains(category.id))
      for (final card in category.cards) ?card.featureKey,
};
