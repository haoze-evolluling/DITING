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

class DesktopRewriteAnswer {
  const DesktopRewriteAnswer({required this.rcode, required this.summary});

  factory DesktopRewriteAnswer.fromJson(Map<String, Object?> json) =>
      DesktopRewriteAnswer(
        rcode: _int(json['rcode']),
        summary: _strings(json['summary']),
      );

  final int rcode;

  final List<String> summary;
}

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

  final String action;
  final String matchedRule;
  final String listName;
  final String reason;
  final DesktopRewriteAnswer? rewritten;

  bool get isRewrite => action == 'rewrite' && rewritten != null;
  bool get isAllow => action == 'allow';
}
