/// What the user asked the model to look at. Split from the prompt builders so the UI can carry a
/// target around (and compare two of them) without dragging the prompt text along.
library;

import 'package:diting_shared/app/l10n/l10n.dart';

sealed class AgentAnalysisTarget {
  const AgentAnalysisTarget();

  /// Panel title, e.g. 域名安全分析.
  String title(AppL10n l10n);

  /// One-line context under the title, so a reopened panel still says what it is about.
  String subtitle(AppL10n l10n);

  /// Domain targets can offer "add to allow/block list"; traffic targets cannot.
  bool get isDomain;
}

/// One domain; [contextLogs] is extra context the caller already holds.
class AgentDomainTarget extends AgentAnalysisTarget {
  const AgentDomainTarget(this.domain, {this.contextLogs = const []});

  final String domain;
  final List<String> contextLogs;

  @override
  String title(AppL10n l10n) => l10n.agentTargetDomainTitle;

  @override
  String subtitle(AppL10n l10n) => domain;

  @override
  bool get isDomain => true;

  // Value equality: the analysis session is keyed on the target, so a rebuild must not look like a
  // new request. `contextLogs` is deliberately excluded — it only refines the prompt.
  @override
  bool operator ==(Object other) =>
      other is AgentDomainTarget && other.domain == domain;

  @override
  int get hashCode => Object.hash(AgentDomainTarget, domain);
}

class AgentTrafficTarget extends AgentAnalysisTarget {
  const AgentTrafficTarget();

  @override
  String title(AppL10n l10n) => l10n.agentTargetTrafficTitle;

  @override
  String subtitle(AppL10n l10n) => l10n.agentTargetTrafficSubtitle;

  @override
  bool get isDomain => false;

  @override
  bool operator ==(Object other) => other is AgentTrafficTarget;

  @override
  int get hashCode => (AgentTrafficTarget).hashCode;
}
