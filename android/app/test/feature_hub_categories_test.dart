// Guards the feature-hub taxonomy after the module split: every category stays small, no card is
// reachable from two places, and the categories that replaced the old 规则控制 sections exist.

import 'package:diting_android/data/mock_data.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = lookupAppL10n(const Locale('zh'));
  final categories = mockFeatureCategories(l10n);

  test('分类覆盖拆分出的模块，且每个分类不过度堆积', () {
    expect(
      categories.map((category) => category.title),
      containsAll(['网络工具与隐私', '自动化与场景', '接口与联动', '订阅与更新']),
    );
    for (final category in categories) {
      expect(category.cards, isNotEmpty, reason: '${category.title} 不应为空分类');
      expect(
        category.cards.length,
        lessThanOrEqualTo(6),
        reason: '${category.title} 卡片过多，应继续拆分',
      );
    }
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
  });
}
