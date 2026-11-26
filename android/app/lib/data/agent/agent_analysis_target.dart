library;

import 'package:diting_android/app/l10n/l10n.dart';

sealed class AgentAnalysisTarget {
  const AgentAnalysisTarget();

  String title(AppL10n l10n);

  String subtitle(AppL10n l10n);

  bool get isDomain;
}

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
