library;

import 'package:diting_android/data/native/rule_test_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final ruleTestBridgeProvider = Provider<RuleTestBridge>(
  (ref) => RuleTestBridge(),
);
