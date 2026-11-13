import 'package:diting_android/data/native/troubleshooting_log_bridge.dart';
import 'package:diting_android/pages/hub/agent_api_page.dart';
import 'package:diting_android/pages/hub/agent_providers_page.dart';
import 'package:diting_android/pages/hub/agent_settings_pages.dart';
import 'package:diting_android/pages/hub/app_rules_page.dart';
import 'package:diting_android/pages/hub/app_selection_pages.dart';
import 'package:diting_android/pages/hub/bootstrap_settings_page.dart';
import 'package:diting_android/pages/hub/ca_certificate_pages.dart';
import 'package:diting_android/pages/hub/cache_settings_page.dart';
import 'package:diting_android/pages/hub/config_transfer_page.dart';
import 'package:diting_android/pages/hub/config_transfer_webdav.dart';
import 'package:diting_android/pages/hub/data_cleanup_page.dart';
import 'package:diting_android/pages/hub/hidden_features_page.dart';
import 'package:diting_android/pages/hub/http_inspection_page.dart';
import 'package:diting_android/pages/hub/log_retention_page.dart';
import 'package:diting_android/pages/hub/outbound_proxy_pages.dart';
import 'package:diting_android/pages/hub/outbound_proxy_targets_page.dart';
import 'package:diting_android/pages/hub/provider_management_page.dart';
import 'package:diting_android/pages/hub/provider_visibility_page.dart';
import 'package:diting_android/pages/hub/recognition_pages.dart';
import 'package:diting_android/pages/hub/resolution_mode_page.dart';
import 'package:diting_android/pages/hub/rule_control_page.dart';
import 'package:diting_android/pages/hub/subscription_tools_pages.dart';
import 'package:diting_android/pages/hub/troubleshooting_log_content_page.dart';
import 'package:diting_android/pages/hub/troubleshooting_logs_page.dart';
import 'package:diting_android/pages/hub/troubleshooting_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:go_router/go_router.dart';

/// Feature hub sub pages under `/hub/*`, one per `FeatureHubScreen.kt` card.
abstract final class HubPaths {
  static const providerManagement = '/hub/providers';
  static const bootstrap = '/hub/bootstrap';
  static const resolution = '/hub/resolution';
  static const cache = '/hub/cache';
  static const ruleControl = '/hub/rules';
  static const blockResponse = '/hub/rules/block-response';
  static const autoUpdate = '/hub/rules/auto-update';
  static const mirrorTemplates = '/hub/rules/mirrors';
  static const appRules = '/hub/app-rules';
  static const blockedApps = '/hub/blocked-apps';
  static const excludedApps = '/hub/excluded-apps';
  static const httpInspection = '/hub/https-inspection';
  static const httpInspectionApps = '/hub/https-inspection/apps';
  static const caCertificate = '/hub/https-inspection/ca';
  static const caGuide = '/hub/https-inspection/ca/guide';
  static const outboundProxy = '/hub/outbound-proxy';
  static const outboundProxyApps = '/hub/outbound-proxy/apps';
  static const outboundProxyTargets = '/hub/outbound-proxy/targets';
  static const agentApi = '/hub/agent';
  static const agentProviders = '/hub/agent/providers';
  static const agentParams = '/hub/agent/params';
  static const providerVisibility = '/hub/provider-visibility';
  static const hiddenFeatures = '/hub/hidden-features';
  static const logRetention = '/hub/log-retention';
  static const troubleshooting = '/hub/troubleshooting';
  static const troubleshootingLogs = '/hub/troubleshooting/logs';
  static const dataCleanup = '/hub/data-cleanup';
  static const configTransfer = '/hub/config-transfer';
  static const configTransferWebdav = '/hub/config-transfer/webdav';
  static const sponsorList = '/hub/sponsor-list';
  static const coBuilders = '/hub/co-builders';

  static String resolutionMode(String id) => '$resolution/$id';

  static String troubleshootingLogContent(String kind, String name) =>
      '$troubleshootingLogs/${Uri.encodeComponent(kind)}/'
      '${Uri.encodeComponent(name)}';
}

List<RouteBase> hubRoutes() => [
  GoRoute(
    path: HubPaths.providerManagement,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ProviderManagementPage()),
  ),
  GoRoute(
    path: HubPaths.bootstrap,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const BootstrapSettingsPage()),
  ),
  GoRoute(
    path: HubPaths.resolution,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ResolutionModePage()),
  ),
  GoRoute(
    path: '${HubPaths.resolution}/:modeId',
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) => androidDefaultPage(
      state,
      ResolutionModeConfigPage(
        modeId: state.pathParameters['modeId'] ?? 'single',
      ),
    ),
  ),
  GoRoute(
    path: HubPaths.cache,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const CacheSettingsPage()),
  ),
  GoRoute(
    path: HubPaths.ruleControl,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const RuleControlPage()),
  ),
  GoRoute(
    path: HubPaths.blockResponse,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const BlockResponsePage()),
  ),
  GoRoute(
    path: HubPaths.autoUpdate,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const AutoUpdateSettingsPage()),
  ),
  GoRoute(
    path: HubPaths.mirrorTemplates,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const MirrorTemplatesPage()),
  ),
  GoRoute(
    path: HubPaths.appRules,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const AppRulesPage()),
  ),
  GoRoute(
    path: HubPaths.blockedApps,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const BlockedAppsPage()),
  ),
  GoRoute(
    path: HubPaths.excludedApps,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ExcludedAppsPage()),
  ),
  GoRoute(
    path: HubPaths.httpInspection,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const HttpInspectionPage()),
  ),
  GoRoute(
    path: HubPaths.httpInspectionApps,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const HttpInspectionAppsPage()),
  ),
  GoRoute(
    path: HubPaths.caCertificate,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const CaCertificatePage()),
  ),
  GoRoute(
    path: HubPaths.caGuide,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const CaCertificateGuidePage()),
  ),
  GoRoute(
    path: HubPaths.outboundProxy,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const OutboundProxyPage()),
  ),
  GoRoute(
    path: HubPaths.outboundProxyApps,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const OutboundProxyAppsPage()),
  ),
  GoRoute(
    path: HubPaths.outboundProxyTargets,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const OutboundProxyTargetsPage()),
  ),
  GoRoute(
    path: HubPaths.agentApi,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const AgentApiPage()),
  ),
  GoRoute(
    path: HubPaths.agentProviders,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const AgentProvidersPage()),
  ),
  GoRoute(
    path: HubPaths.agentParams,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const AgentParamsPage()),
  ),
  GoRoute(
    path: HubPaths.providerVisibility,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ProviderVisibilityPage()),
  ),
  GoRoute(
    path: HubPaths.hiddenFeatures,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const HiddenFeaturesPage()),
  ),
  GoRoute(
    path: HubPaths.logRetention,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const LogRetentionPage()),
  ),
  GoRoute(
    path: HubPaths.troubleshooting,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const TroubleshootingPage()),
  ),
  GoRoute(
    path: HubPaths.troubleshootingLogs,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const TroubleshootingLogsPage()),
  ),
  GoRoute(
    path: '${HubPaths.troubleshootingLogs}/:kind/:name',
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) => androidDefaultPage(
      state,
      TroubleshootingLogContentPage(
        kind:
            TroubleshootLogKind.fromTag(state.pathParameters['kind']) ??
            TroubleshootLogKind.runtime,
        name: state.pathParameters['name'] ?? '',
      ),
    ),
  ),
  GoRoute(
    path: HubPaths.dataCleanup,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const DataCleanupPage()),
  ),
  GoRoute(
    path: HubPaths.configTransfer,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ConfigTransferPage()),
  ),
  GoRoute(
    path: HubPaths.configTransferWebdav,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const ConfigTransferWebdavPage()),
  ),
  GoRoute(
    path: HubPaths.sponsorList,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const SponsorListPage()),
  ),
  GoRoute(
    path: HubPaths.coBuilders,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const CoBuildersPage()),
  ),
];
