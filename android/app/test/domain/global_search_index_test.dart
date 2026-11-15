import 'package:diting_android/data/global_search_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const entries = [
    GlobalSearchEntry(
      title: 'DNS 缓存',
      subtitle: '缓存设置',
      route: '/hub/cache',
      group: 'DNS',
      keywords: ['memory', 'cache'],
    ),
    GlobalSearchEntry(
      title: '规则测试',
      route: '/hub/rules/test',
      group: '常用命令',
    ),
    GlobalSearchEntry(
      title: '保护健康',
      route: '/health',
      group: '常用命令',
      keywords: ['health'],
    ),
  ];

  test('an empty or whitespace query yields no results', () {
    expect(filterGlobalSearch(entries, ''), isEmpty);
    expect(filterGlobalSearch(entries, '   '), isEmpty);
  });

  test('matches title, subtitle, group and keywords', () {
    expect(
      filterGlobalSearch(entries, 'cache').map((e) => e.route),
      ['/hub/cache'],
    );
    expect(
      filterGlobalSearch(entries, '健康').map((e) => e.route),
      ['/health'],
    );
    // 分组名 DNS 也应命中。
    expect(
      filterGlobalSearch(entries, 'dns').map((e) => e.route),
      ['/hub/cache'],
    );
    expect(
      filterGlobalSearch(entries, '规则').map((e) => e.route),
      ['/hub/rules/test'],
    );
  });

  test('an unmatched query yields nothing', () {
    expect(filterGlobalSearch(entries, 'zzz'), isEmpty);
  });
}
