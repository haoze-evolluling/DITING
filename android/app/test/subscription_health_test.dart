import 'package:diting_android/data/subscriptions/rust_subscription_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('health.classify (native)', () {
    final core = RustSubscriptionCore.instance;

    String status(Map<String, Object?> overrides) {
      final answer = core.call({
        'op': 'health.classify',
        'importState': 'ready',
        'ruleCount': 0,
        'lastUpdated': 0,
        ...overrides,
      });
      return answer['status'] as String? ?? '';
    }

    test('a fresh download is ok', () {
      expect(status({'ruleCount': 5, 'lastUpdated': 100}), 'ok');
    });

    test('a failed import with old rules stays cached', () {
      expect(
        status({'importState': 'failed', 'ruleCount': 5, 'lastUpdated': 100}),
        'cached',
      );
    });

    test('a failed import with no rules is failed', () {
      expect(status({'importState': 'failed'}), 'failed');
    });

    test('a live 304 is unchanged', () {
      expect(
        status({'ruleCount': 5, 'lastUpdated': 100, 'lastResult': 'unchanged'}),
        'unchanged',
      );
    });
  });
}
