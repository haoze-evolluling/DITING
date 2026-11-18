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
import 'package:diting_android/pages/rules/block_pause_page.dart';
import 'package:diting_android/pages/rules/rule_test_page.dart';
import 'package:diting_android/pages/hub/subscription_tools_pages.dart';
import 'package:diting_android/pages/hub/troubleshooting_events_page.dart';
import 'package:diting_android/pages/hub/troubleshooting_log_content_page.dart';
import 'package:diting_android/pages/hub/troubleshooting_logs_page.dart';
import 'package:diting_android/pages/hub/troubleshooting_page.dart';
import 'package:diting_shared/routes/page.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Feature hub sub pages under `/hub/*`, one per `FeatureHubScreen.kt` card.
abstract final class HubPaths {
  static const providerManagement = '/hub/providers';
  static const bootstrap = '/hub/bootstrap';
  static const resolution = '/hub/resolution';
  static const cache = '/hub/cache';
  static const ruleControl = '/hub/rules';
  static const ruleTest = '/hub/rules/test';
  static const blockPause = '/hub/rules/pause';
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
  static const troubleshootingEvents = '/hub/troubleshooting/events';
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

/// A full-screen hub page on the root navigator, the shape every leaf route shares.
GoRoute _route(String path, Widget page) => GoRoute(
  path: path,
  parentNavigatorKey: rootNavigatorKey,
  pageBuilder: (context, state) => androidDefaultPage(state, page),
);

List<RouteBase> hubRoutes() => [
  _route(HubPaths.providerManagement, const ProviderManagementPage()),
  _route(HubPaths.bootstrap, const BootstrapSettingsPage()),
  _route(HubPaths.resolution, const ResolutionModePage()),
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
  _route(HubPaths.cache, const CacheSettingsPage()),
  _route(HubPaths.ruleControl, const RuleControlPage()),
  GoRoute(
    path: HubPaths.ruleTest,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) => androidDefaultPage(
      state,
      RuleTestPage(initialDomain: state.uri.queryParameters['domain']),
    ),
  ),
  _route(HubPaths.blockPause, const BlockPausePage()),
  _route(HubPaths.blockResponse, const BlockResponsePage()),
  _route(HubPaths.autoUpdate, const AutoUpdateSettingsPage()),
  _route(HubPaths.mirrorTemplates, const MirrorTemplatesPage()),
  _route(HubPaths.appRules, const AppRulesPage()),
  _route(HubPaths.blockedApps, const BlockedAppsPage()),
  _route(HubPaths.excludedApps, const ExcludedAppsPage()),
  _route(HubPaths.httpInspection, const HttpInspectionPage()),
  _route(HubPaths.httpInspectionApps, const HttpInspectionAppsPage()),
  _route(HubPaths.caCertificate, const CaCertificatePage()),
  _route(HubPaths.caGuide, const CaCertificateGuidePage()),
  _route(HubPaths.outboundProxy, const OutboundProxyPage()),
  _route(HubPaths.outboundProxyApps, const OutboundProxyAppsPage()),
  _route(HubPaths.outboundProxyTargets, const OutboundProxyTargetsPage()),
  _route(HubPaths.agentApi, const AgentApiPage()),
  _route(HubPaths.agentProviders, const AgentProvidersPage()),
  _route(HubPaths.agentParams, const AgentParamsPage()),
  _route(HubPaths.providerVisibility, const ProviderVisibilityPage()),
  _route(HubPaths.hiddenFeatures, const HiddenFeaturesPage()),
  _route(HubPaths.logRetention, const LogRetentionPage()),
  _route(HubPaths.troubleshooting, const TroubleshootingPage()),
  _route(HubPaths.troubleshootingLogs, const TroubleshootingLogsPage()),
  _route(HubPaths.troubleshootingEvents, const TroubleshootingEventsPage()),
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
  _route(HubPaths.dataCleanup, const DataCleanupPage()),
  _route(HubPaths.configTransfer, const ConfigTransferPage()),
  _route(HubPaths.configTransferWebdav, const ConfigTransferWebdavPage()),
  _route(HubPaths.sponsorList, const SponsorListPage()),
  _route(HubPaths.coBuilders, const CoBuildersPage()),
];
