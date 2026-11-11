library;

import 'package:diting_shared/app/l10n/l10n.dart';

/// Cards of the server-mode home dashboard.
///
/// Mirrors [DashboardWidget] on the normal/express home so the three modes share one dashboard
/// look, but every card reports DNS-server state or opens a server-mode module. Persisted by
/// [name], so renaming a value drops it from a stored layout instead of corrupting it.
enum ServerDashboardWidget {
  /// Service state, uptime and this run's query counters.
  status,

  /// Resolution mode plus the selected upstream / race candidates; opens the upstream editor.
  upstream,

  /// LAN address and port peers should point their DNS at.
  lanAccess,

  /// Cache switch and preset summary; opens the cache settings page.
  cache,

  /// Rule master switch summary; opens the rule control page.
  ruleControl,

  /// Shortcuts to the blocklist, allowlist and host-override tables.
  domainRules;

  String label(AppL10n l10n) => switch (this) {
    ServerDashboardWidget.status => l10n.serverServiceStatus,
    ServerDashboardWidget.upstream => l10n.serverCurrentUpstreamCard,
    ServerDashboardWidget.lanAccess => l10n.serverLanAccess,
    ServerDashboardWidget.cache => l10n.serverCacheSettings,
    ServerDashboardWidget.ruleControl => l10n.serverRuleControl,
    ServerDashboardWidget.domainRules => l10n.serverDomainRules,
  };

  /// One-line explanation shown in the add-card sheet.
  String description(AppL10n l10n) => switch (this) {
    ServerDashboardWidget.status => l10n.serverDashboardStatusDescription,
    ServerDashboardWidget.upstream => l10n.serverHubUpstreamDescription,
    ServerDashboardWidget.lanAccess => l10n.serverDashboardLanDescription,
    ServerDashboardWidget.cache => l10n.serverHubCacheDescription,
    ServerDashboardWidget.ruleControl => l10n.serverHubRuleControlDescription,
    ServerDashboardWidget.domainRules => l10n.serverDomainRulesDescription,
  };
}

/// Order a fresh install shows, most-used operation state first.
const defaultServerDashboardWidgets = <ServerDashboardWidget>[
  ServerDashboardWidget.status,
  ServerDashboardWidget.upstream,
  ServerDashboardWidget.lanAccess,
  ServerDashboardWidget.cache,
  ServerDashboardWidget.ruleControl,
  ServerDashboardWidget.domainRules,
];
