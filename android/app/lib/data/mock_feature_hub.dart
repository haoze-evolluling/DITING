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

  /// Whether express mode (the narrow DNS-only route) shows the card.
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
/// Information architecture — the hub is grouped by **what the feature does and when a user
/// reaches for it**, not by where the code lives. Six purpose-based sections with four cards each,
/// plus 应用流量统计 and 日志仪表盘, which also live in the bottom dock but now have a hub entry,
/// and 前后台行为, moved here from 其他设置. 应用与网络 holds five cards, 数据与维护 six. The last
/// card keeps the half-width column so rows stay aligned. The three work modes share one layout:
///
///   1. DNS 解析       服务商 / 策略 / 缓存 / 服务显示
///   2. 规则与控制     拦截策略 / 规则订阅 / 应用规则 / 隐私套件
///   3. 应用与网络     实时连接 / 应用洞察 / 网络工具 / 连接限速 / 应用流量统计
///   4. 高级与诊断     网络诊断 / HTTPS 检查 / 出站代理 / AI 分析
///   5. 数据与维护     备份迁移 / 数据清理 / 故障排查 / 日志模式 / 日志仪表盘 / 前后台行为
///   6. 界面与数据     外观 / 隐藏功能 / 其他设置 / 关于
///
/// Low-frequency functions stay folded into a parent page's secondary "更多功能" section instead
/// of taking a first-class card:
///   - 解析服务商 → 引导解析
///   - 解析策略 → DNS64
///   - 规则控制 → 域名黑名单 / 域名白名单 / 域名覆写 / 规则测试 / 临时暂停 / 拦截响应 / 场景自动化
///   - 规则订阅 → 自动更新 / 镜像模板 / 版本回滚 / User-Agent 管理
///   - 应用规则 → 禁止联网应用 / 排除应用
///   - 应用流量/日志 keep their dock entry and open full screen from the hub; 网络工具/设置 are
///     also full-screen entries from the dock.
///
/// Express mode (DNS-only) keeps only the sections that still apply and hides the tunnel-bound
/// ones (应用与网络 / 高级与诊断), so it never offers an entry whose switches cannot take effect.
List<MockFeatureCategory> mockFeatureCategories(AppL10n l10n) =>
    <MockFeatureCategory>[
  MockFeatureCategory(
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
    title: l10n.hubCategoryNetwork,
    cards: [
      MockFeatureCard(
        title: l10n.flowTitle,
        description: l10n.flowEntrySubtitle,
        glyphName: 'connections',
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
        title: l10n.bottomBarNetworkTools,
        description: l10n.hubDiagnosticsDescription,
        glyphName: 'tools',
        route: '/tools',
        featureKey: 'network_tools',
        expressVisible: false,
      ),
      MockFeatureCard(
        title: l10n.connectionRateLimitTitle,
        description: l10n.connectionRateLimitCardDescription,
        glyphName: 'speed',
        route: '/network/connection-rate-limit',
        featureKey: 'connection_rate_limit',
        expressVisible: false,
      ),
      MockFeatureCard(
        title: l10n.hubAppTraffic,
        description: l10n.hubAppTrafficDescription,
        glyphName: 'dataUsage',
        route: '/traffic',
        featureKey: 'traffic_stats',
        expressVisible: false,
      ),
    ],
  ),
  MockFeatureCategory(
    title: l10n.hubCategoryAdvanced,
    cards: [
      MockFeatureCard(
        title: l10n.hubDiagnostics,
        description: l10n.networkDiagnosticsIntro,
        glyphName: 'target',
        route: '/network/diagnostics',
        featureKey: 'network_diagnostics',
        expressVisible: false,
      ),
      MockFeatureCard(
        title: l10n.hubHttpsInspection,
        description: l10n.hubHttpsInspectionDescription,
        glyphName: 'lock',
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
    ],
  ),
  MockFeatureCategory(
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
        title: l10n.hubDataCleanup,
        description: l10n.hubDataCleanupDescription,
        glyphName: 'broom',
        route: '/hub/data-cleanup',
        featureKey: 'data_cleanup',
      ),
      MockFeatureCard(
        title: l10n.hubTroubleshooting,
        description: l10n.hubTroubleshootingDescription,
        glyphName: 'stethoscope',
        route: '/hub/troubleshooting',
        featureKey: 'troubleshooting',
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
        title: l10n.foregroundTitle,
        description: l10n.settingsForegroundSubtitle,
        glyphName: 'eyeOff',
        route: '/settings/background',
        featureKey: 'foreground_behavior',
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
