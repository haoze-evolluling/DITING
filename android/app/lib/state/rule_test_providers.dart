/// Providers for the rule-test simulator (R1). The bridge is a provider so a widget test can inject
/// a fake, and so the page never builds a channel itself.
library;

import 'package:diting_android/data/native/rule_test_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The real MethodChannel bridge; overridden in tests.
final ruleTestBridgeProvider = Provider<RuleTestBridge>(
  (ref) => RuleTestBridge(),
);
