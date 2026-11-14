import 'package:diting_android/data/native/block_pause_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BlockPauseState parses and reports paused/remaining', () {
    final until = DateTime.now()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    final state = BlockPauseState.fromMap({
      'pausedUntilMs': until,
      'allowlistOnly': true,
    });
    expect(state.paused, isTrue);
    expect(state.allowlistOnly, isTrue);
    expect(state.remaining.inMinutes, inInclusiveRange(4, 5));
  });

  test('a zero deadline is not paused', () {
    final state = BlockPauseState.fromMap({
      'pausedUntilMs': 0,
      'allowlistOnly': false,
    });
    expect(state.paused, isFalse);
    expect(state.remaining, Duration.zero);
  });

  test('a past deadline is not paused', () {
    final past = DateTime.now()
        .subtract(const Duration(minutes: 1))
        .millisecondsSinceEpoch;
    expect(BlockPauseState.fromMap({'pausedUntilMs': past}).paused, isFalse);
  });
}
