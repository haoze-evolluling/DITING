/// The rule simulator: `POST /api/v1/filter/check`.
///
/// The old desktop console's `RuleTestPanel.vue` is the blueprint. The service answers with the
/// verdict, the rule that produced it, the list it came from and, for a `$dnsrewrite` hit, the
/// records the answer would carry. The page repeats that verdict; it does not re-derive it.
library;

bool _bool(Object? value) => value == true;

int _int(Object? value) => switch (value) {
  num() => value.toInt(),
  String() => int.tryParse(value) ?? 0,
  _ => 0,
};

List<String> _strings(Object? value) => switch (value) {
  List() => [for (final item in value) '$item'],
  _ => const [],
};

/// The answer a `$dnsrewrite` rule would return.
class DesktopRewriteAnswer {
  const DesktopRewriteAnswer({required this.rcode, required this.summary});

  factory DesktopRewriteAnswer.fromJson(Map<String, Object?> json) =>
      DesktopRewriteAnswer(
        rcode: _int(json['rcode']),
        summary: _strings(json['summary']),
      );

  final int rcode;

  /// The records in their presentation form; empty on an explicit NODATA answer.
  final List<String> summary;
}

/// `GET`-less: the result of one simulated lookup.
class DesktopRuleCheckResult {
  const DesktopRuleCheckResult({
    required this.blocked,
    required this.action,
    required this.matchedRule,
    required this.listName,
    required this.reason,
    required this.rewritten,
  });

  factory DesktopRuleCheckResult.fromJson(Map<String, Object?> json) {
    final rewritten = json['rewritten'];
    return DesktopRuleCheckResult(
      blocked: _bool(json['blocked']),
      action: '${json['action'] ?? ''}',
      matchedRule: '${json['matchedRule'] ?? ''}',
      listName: '${json['listName'] ?? ''}',
      reason: '${json['reason'] ?? ''}',
      rewritten: rewritten is Map
          ? DesktopRewriteAnswer.fromJson(rewritten.cast<String, Object?>())
          : null,
    );
  }

  final bool blocked;

  /// `block`, `allow`, `rewrite` or `pass`.
  final String action;
  final String matchedRule;
  final String listName;
  final String reason;
  final DesktopRewriteAnswer? rewritten;

  bool get isRewrite => action == 'rewrite' && rewritten != null;
  bool get isAllow => action == 'allow';
}
