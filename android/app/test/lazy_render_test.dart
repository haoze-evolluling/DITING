// Regression guard for the bulk-list pages: rows behind the viewport must not
// be built in the first frame. The rule tables froze the app this way
// (2026-10-27 ANR, 191,090 rows).

import 'package:diting_android/data/db/dns_cache_repository.dart';
import 'package:diting_android/data/db/rule_providers.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/pages/logs/logs_cache_page.dart';
import 'package:diting_android/pages/rules/rules_page.dart';
import 'package:diting_android/state/log_dashboard_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/section_slivers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_host.dart';

void main() {
  group('惰性区段', _lazySections);
  group('规则表惰性渲染', _rulesPageLazy);
}

void _lazySections() {
  testWidgets('惰性区段首帧只构建可见行', (tester) async {
    await tester.pumpWidget(
      AppHost(
        child: CustomScrollView(
          slivers: [
            ...lazySectionSlivers(
              title: '条目',
              itemCount: 5000,
              itemBuilder: (context, index) =>
                  ListItem(title: Text('row-$index')),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('条目'), findsOneWidget);
    expect(find.text('row-0'), findsOneWidget);
    // Far below the viewport, so never inflated.
    expect(find.text('row-4000'), findsNothing);
  });

  testWidgets('DNS 缓存表只构建可见行', (tester) async {
    final overrides = <Override>[
      dnsCacheProvider.overrideWith((ref) async => _entries(200)),
      cacheLastHitProvider.overrideWith((ref) async => const <String, int?>{}),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const AppHost(child: LogsCachePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('cache-0.example'), findsOneWidget);
    // Row 150 of 200 sits well below a 891 pt viewport.
    expect(find.text('cache-150.example'), findsNothing);
  });
}

// Regression guard for the bulk-list pages: rows behind the viewport must not be built in the
// first frame. The rule tables froze the app this way (2026-10-27 ANR, 191,090 rows), and every
// other large list in the app now goes through `lazySectionSlivers`.
// `Override` is only exported from `misc.dart`

List<DnsCacheRecord> _entries(int count) => [
  for (var i = 0; i < count; i++)
    DnsCacheRecord(
      domain: 'cache-$i.example',
      queryType: 1,
      expiresAt: DateTime.now().millisecondsSinceEpoch + 300 * 1000,
      hitCount: i,
      originalTtlSeconds: 300,
      responseSize: 64,
    ),
];

void _rulesPageLazy() {
  testWidgets('订阅级规则表首帧只构建可见行', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialRulesProvider.overrideWith(
            () =>
                _FixedInitialRules({RuleKind.block: _subscriptionRules(20000)}),
          ),
        ],
        child: const AppHost(child: RulesPage(kind: 'block')),
      ),
    );
    await tester.pumpAndSettle();

    // The caption reports the whole table without the list having been built.
    expect(find.text('共 20000 条 · 启用 20000'), findsOneWidget);
    // First rows are laid out; rows far below the viewport were never inflated.
    expect(find.text('rule-0.example'), findsOneWidget);
    expect(find.text('rule-15000.example'), findsNothing);
  });
}

// Regression for the 2026-10-27 ANR: a subscription-sized rule table must not be inflated in the
// first frame. The page builds rows lazily, so only the viewport's rows exist.

/// Fixed state for one-shot override of the initial-rules provider.
class _FixedInitialRules extends InitialRulesNotifier {
  _FixedInitialRules(this._initial);

  final Map<RuleKind, List<MockRule>> _initial;

  @override
  Map<RuleKind, List<MockRule>> build() => _initial;
}

List<MockRule> _subscriptionRules(int count) => [
  for (var i = 0; i < count; i++)
    MockRule(
      id: '$i',
      pattern: 'rule-$i.example',
      kind: RuleKind.block,
      source: RuleSource.subscription,
      subscriptionName: 'filter_1.txt',
    ),
];
