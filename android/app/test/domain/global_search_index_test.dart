import 'package:diting_android/data/global_search_index.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:flutter/widgets.dart' show Locale;
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
    GlobalSearchEntry(title: '规则测试', route: '/hub/rules/test', group: '常用命令'),
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
    expect(filterGlobalSearch(entries, 'cache').map((e) => e.route), [
      '/hub/cache',
    ]);
    expect(filterGlobalSearch(entries, '健康').map((e) => e.route), ['/health']);
    expect(filterGlobalSearch(entries, 'dns').map((e) => e.route), [
      '/hub/cache',
    ]);
    expect(filterGlobalSearch(entries, '规则').map((e) => e.route), [
      '/hub/rules/test',
    ]);
  });

  test('an unmatched query yields nothing', () {
    expect(filterGlobalSearch(entries, 'zzz'), isEmpty);
  });

  test('connection rate limiting is indexed for every tunnel mode', () {
    final l10n = lookupAppL10n(const Locale('zh'));
    final entries = buildGlobalSearchIndex(l10n);
    expect(
      entries.map((entry) => entry.route),
      contains('/network/connection-rate-limit'),
    );
  });
}
