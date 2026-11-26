import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = lookupAppL10n(const Locale('zh'));
  final categories = mockFeatureCategories(l10n);

  test('分类非空且关键入口可达', () {
    expect(categories.map((category) => category.title).toList(), [
      'DNS 解析',
      '规则与控制',
      '应用与网络',
      '高级与诊断',
      '数据与维护',
      '界面与数据',
    ]);
    expect(categories.length, 6);
    const cardCounts = {'数据与维护': 6};
    for (final category in categories) {
      expect(category.cards, isNotEmpty, reason: '${category.title} 不应为空分类');
      expect(
        category.cards.length,
        cardCounts[category.title] ?? 4,
        reason: '${category.title} 卡片数量应符合布局约定',
      );
    }
    final total = categories.fold<int>(
      0,
      (sum, category) => sum + category.cards.length,
    );
    expect(total, 26);
    final network = categories.firstWhere(
      (category) => category.title == '应用与网络',
    );
    expect(network.cards.map((card) => card.title), contains('连接限速'));
    expect(network.cards.map((card) => card.title), isNot(contains('局域网限速')));
    expect(
      network.cards.map((card) => card.route),
      contains('/traffic'),
      reason: '应用流量统计应可从功能中心进入',
    );
    final data = categories.firstWhere((category) => category.title == '数据与维护');
    expect(
      data.cards.map((card) => card.route),
      contains('/logs'),
      reason: '日志仪表盘应可从功能中心进入',
    );
    expect(
      data.cards.map((card) => card.route),
      contains('/settings/background'),
      reason: '前后台行为应可从功能中心进入',
    );
  });

  test('普通模式显示全部卡片，简洁模式移除依赖隧道的入口', () {
    final visible = visibleFeatureCategories(hiddenKeys: const {}, l10n: l10n);
    expect(visible.map((category) => category.title), [
      for (final category in categories) category.title,
    ]);
    final cards = [for (final category in visible) ...category.cards];
    expect(cards.map((card) => card.featureKey), [
      for (final category in categories)
        for (final card in category.cards) card.featureKey,
    ]);
    expect(
      cards.map((card) => card.featureKey),
      containsAll(<String>[
        'connection_rate_limit',
        'traffic_stats',
        'https_inspection',
        'outbound_proxy',
      ]),
    );

    final express = visibleFeatureCategories(
      hiddenKeys: const {},
      l10n: l10n,
      excludedKeys: tunnelOnlyFeatureKeys,
    );
    final expressKeys = [
      for (final category in express)
        for (final card in category.cards) ?card.featureKey,
    ];
    expect(expressKeys.toSet().intersection(tunnelOnlyFeatureKeys), isEmpty);
    expect(expressKeys, isNot(contains('app_rules')));
    expect(expressKeys, contains('rule_control'));
    expect(expressKeys, contains('logs'));
  });

  test('卡片路由与隐藏键都不重复', () {
    final routes = [
      for (final category in categories)
        for (final card in category.cards) card.route,
    ];
    expect(routes.toSet().length, routes.length, reason: '同一页面不应有两个入口');

    final keys = [
      for (final category in categories)
        for (final card in category.cards) ?card.featureKey,
    ];
    expect(keys.toSet().length, keys.length, reason: '隐藏键必须唯一');

    const folded = {
      'bootstrap_settings',
      'dns64',
      'blacklist',
      'whitelist',
      'rewrite_list',
      'auto_update',
      'mirror_templates',
      'automation',
      'automation_profiles',
      'custom_resources',
      'timetable',
      'network_profile',
      'blocked_apps',
      'excluded_apps',
      'request_logs',
      'sponsor',
      'sponsor_list',
      'contributors',
      'ip_quality',
    };
    expect(keys.toSet().intersection(folded), isEmpty);
  });
}
