/// Dart side of the rule-test simulator (R1), `com.haoze.diting/rule_test`.
///
/// The verdict itself is produced by `rust/diting-engine` through the Kotlin bridge: this file only
/// types the JSON, so there is no second policy implementation in Dart. The snapshot the bridge
/// evaluates is the same `RuleSnapshotStore` document the engine is fed, so "why blocked" cannot
/// drift from the running filter.
library;

import 'package:flutter/services.dart';

/// What the policy walk decided for one query.
enum RuleTestAction {
  block,
  allow,
  pass;

  static RuleTestAction fromStorage(String? value) => switch (value) {
    'block' => block,
    'allow' => allow,
    _ => pass,
  };
}

/// The rewrite the pipeline would apply to the queried domain, when a rewrite rule matches.
class RuleTestRewrite {
  const RuleTestRewrite({this.cname = '', this.ip4 = '', this.ip6 = ''});

  final String cname;
  final String ip4;
  final String ip6;

  bool get isEmpty => cname.isEmpty && ip4.isEmpty && ip6.isEmpty;

  /// `CNAME → …`, `A → …`, `AAAA → …`, one per non-empty target.
  List<String> get entries => [
    if (cname.isNotEmpty) 'CNAME → $cname',
    if (ip4.isNotEmpty) 'A → $ip4',
    if (ip6.isNotEmpty) 'AAAA → $ip6',
  ];

  static RuleTestRewrite fromMap(Map<Object?, Object?> map) => RuleTestRewrite(
    cname: map['cname'] as String? ?? '',
    ip4: map['ip4'] as String? ?? '',
    ip6: map['ip6'] as String? ?? '',
  );
}

/// The whole verdict: action, the matched rule pattern (the engine's own `reason`), and any rewrite.
class RuleTestResult {
  const RuleTestResult({
    required this.action,
    required this.blocked,
    required this.reason,
    this.rewrite,
  });

  final RuleTestAction action;
  final bool blocked;

  /// The matched pattern exactly as the engine logs it, or `__ALLOW__`, or empty on a plain pass.
  final String reason;
  final RuleTestRewrite? rewrite;

  /// The rule pattern to show as "命中规则"; empty for a plain pass and for the `__ALLOW__` marker.
  String? get matchedRule =>
      reason.isEmpty || reason == '__ALLOW__' ? null : reason;

  factory RuleTestResult.fromMap(Map<Object?, Object?> map) {
    final rawRewrite = map['rewrite'];
    return RuleTestResult(
      action: RuleTestAction.fromStorage(map['action'] as String?),
      blocked: map['blocked'] == true,
      reason: map['reason'] as String? ?? '',
      rewrite: rawRewrite is Map
          ? RuleTestRewrite.fromMap(Map<Object?, Object?>.from(rawRewrite))
          : null,
    );
  }
}

/// Thrown when the platform cannot build the snapshot or the native check failed.
class RuleTestException implements Exception {
  RuleTestException(this.message);

  final String message;

  @override
  String toString() => 'RuleTestException: $message';
}

/// Method-channel access to the Kotlin bridge.
class RuleTestBridge {
  RuleTestBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'com.haoze.diting/rule_test';

  final MethodChannel _channel;

  /// Runs one simulation for [domain]. [qtype] is a DNS type number (1 = A, 28 = AAAA, 0 = any);
  /// [dataset] selects the rule set (`normal` / `express` / `server`).
  Future<RuleTestResult> check({
    required String domain,
    int qtype = 1,
    String app = '',
    String dataset = 'normal',
  }) async {
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>('check', {
        'domain': domain,
        'qtype': qtype,
        'app': app,
        'dataset': dataset,
      });
      if (map == null) {
        throw RuleTestException('empty answer');
      }
      return RuleTestResult.fromMap(map);
    } on PlatformException catch (error) {
      throw RuleTestException(error.message ?? error.code);
    } on MissingPluginException {
      throw RuleTestException('rule-test channel unavailable');
    }
  }
}
