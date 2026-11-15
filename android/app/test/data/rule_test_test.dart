import 'package:diting_android/data/native/rule_test_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuleTestResult.fromMap', () {
    test('blocked query exposes the matched rule pattern', () {
      final result = RuleTestResult.fromMap({
        'action': 'block',
        'blocked': true,
        'reason': 'ads.example.com',
        'rewrite': null,
      });
      expect(result.action, RuleTestAction.block);
      expect(result.blocked, isTrue);
      expect(result.matchedRule, 'ads.example.com');
      expect(result.rewrite, isNull);
    });

    test('an explicit allow has no matched rule to show', () {
      final result = RuleTestResult.fromMap({
        'action': 'allow',
        'blocked': false,
        'reason': '__ALLOW__',
      });
      expect(result.action, RuleTestAction.allow);
      expect(result.blocked, isFalse);
      expect(result.matchedRule, isNull);
    });

    test('a plain pass carries no reason', () {
      final result = RuleTestResult.fromMap({
        'action': 'pass',
        'blocked': false,
        'reason': '',
      });
      expect(result.action, RuleTestAction.pass);
      expect(result.matchedRule, isNull);
      expect(result.rewrite, isNull);
    });

    test('a rewrite entry is rendered one line per non-empty target', () {
      final result = RuleTestResult.fromMap({
        'action': 'pass',
        'blocked': false,
        'reason': '',
        'rewrite': {'cname': 'alias.test', 'ip4': '1.2.3.4', 'ip6': ''},
      });
      expect(result.rewrite, isNotNull);
      expect(result.rewrite!.entries, ['CNAME → alias.test', 'A → 1.2.3.4']);
    });

    test('an unknown action falls back to pass', () {
      final result = RuleTestResult.fromMap({
        'action': 'nonsense',
        'blocked': false,
        'reason': '',
      });
      expect(result.action, RuleTestAction.pass);
    });
  });
}
