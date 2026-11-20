import 'package:diting_android/data/mock_data.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = lookupAppL10n(const Locale('zh'));
  final categories = mockFeatureCategories(l10n);

  test('6 个分类共 26 张，数据与维护补两张入口', () {
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

  test('极速模式不提供连接限速', () {
    final visible = visibleFeatureCategories(
      express: true,
      hiddenKeys: const {},
      l10n: l10n,
    );
    expect(visible, isNotEmpty);
    for (final category in visible) {
      expect(
        category.cards.every((card) => card.expressVisible),
        isTrue,
        reason: '${category.title} 不应出现极速隐藏卡片',
      );
    }
    final titles = visible.map((category) => category.title);
    expect(titles, isNot(contains('应用与网络')));
    expect(titles, isNot(contains('高级与诊断')));
    final cards = [for (final category in visible) ...category.cards];
    expect(
      cards.map((card) => card.featureKey),
      isNot(contains('connection_rate_limit')),
    );
    expect(
      cards.map((card) => card.featureKey),
      isNot(contains('traffic_stats')),
    );
    expect(cards.map((card) => card.featureKey), contains('logs'));
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
