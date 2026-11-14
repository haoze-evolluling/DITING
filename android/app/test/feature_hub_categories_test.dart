// Guards the feature-hub taxonomy after the ~24-module consolidation: six small categories, four
// cards each (even, so the two-column grid never leaves a blank cell), and no card reachable from
// two places.

import 'package:diting_android/data/mock_data.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = lookupAppL10n(const Locale('zh'));
  final categories = mockFeatureCategories(l10n);

  test('6 个分类、每类 4 张、共 24 张且每类偶数', () {
    expect(
      categories.map((category) => category.title).toList(),
      ['DNS 解析', '规则与控制', '接口与联动', '界面与数据', '应用与网络', '高级与诊断'],
    );
    expect(categories.length, 6);
    for (final category in categories) {
      expect(category.cards, isNotEmpty, reason: '${category.title} 不应为空分类');
      expect(
        category.cards.length,
        4,
        reason: '${category.title} 应为 4 张卡片',
      );
      expect(category.cards.length.isEven, isTrue);
    }
    final total = categories.fold<int>(
      0,
      (sum, category) => sum + category.cards.length,
    );
    expect(total, 24);
  });

  test('极速模式每个非空分类仍为偶数', () {
    final visible = visibleFeatureCategories(
      express: true,
      hiddenKeys: const {},
      l10n: l10n,
    );
    expect(visible, isNotEmpty);
    for (final category in visible) {
      expect(
        category.cards.length.isEven,
        isTrue,
        reason: '${category.title} 极速模式卡片数应为偶数',
      );
      expect(
        category.cards.every((card) => card.expressVisible),
        isTrue,
        reason: '${category.title} 不应出现极速隐藏卡片',
      );
    }
    // 应用与网络、高级与诊断两类在极速模式全部隐藏，整体不出现。
    final titles = visible.map((category) => category.title);
    expect(titles, isNot(contains('应用与网络')));
    expect(titles, isNot(contains('高级与诊断')));
  });

  test('卡片路由与隐藏键都不重复', () {
    final routes = [
      for (final category in categories)
        for (final card in category.cards) card.route,
    ];
    expect(routes.toSet().length, routes.length, reason: '同一页面不应有两个入口');

    final keys = [
      for (final category in categories)
        for (final card in category.cards)
          if (card.featureKey case final key?) key,
    ];
    expect(keys.toSet().length, keys.length, reason: '隐藏键必须唯一');

    // 低频功能已下沉为父页面二级入口，不再占用一级卡片。
    const folded = {
      'bootstrap_settings',
      'service_display',
      'blacklist',
      'whitelist',
      'rewrite_list',
      'auto_update',
      'mirror_templates',
      'automation_profiles',
      'timetable',
      'network_profile',
      'traffic_stats',
      'blocked_apps',
      'excluded_apps',
      'request_logs',
      'logs',
      'data_cleanup',
      'troubleshooting',
      'sponsor',
      'sponsor_list',
      'contributors',
      'other_settings',
      'ip_quality',
    };
    expect(keys.toSet().intersection(folded), isEmpty);
  });
}
