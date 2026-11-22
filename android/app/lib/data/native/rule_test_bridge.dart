library;

import 'package:flutter/services.dart';

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

class RuleTestRewrite {
  const RuleTestRewrite({this.cname = '', this.ip4 = '', this.ip6 = ''});

  final String cname;
  final String ip4;
  final String ip6;

  bool get isEmpty => cname.isEmpty && ip4.isEmpty && ip6.isEmpty;

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

class RuleTestResult {
  const RuleTestResult({
    required this.action,
    required this.blocked,
    required this.reason,
    this.rewrite,
  });

  final RuleTestAction action;
  final bool blocked;

  final String reason;
  final RuleTestRewrite? rewrite;

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

class RuleTestException implements Exception {
  RuleTestException(this.message);

  final String message;

  @override
  String toString() => 'RuleTestException: $message';
}

class RuleTestBridge {
  RuleTestBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'com.haoze.diting/rule_test';

  final MethodChannel _channel;

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
