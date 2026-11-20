library;

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_client_groups_models.dart';
import 'package:diting_desktop/data/api/desktop_rule_check_models.dart';
import 'package:diting_desktop/data/api/desktop_tools_models.dart';
import 'package:diting_desktop/data/api/desktop_traffic_models.dart';
import 'package:diting_desktop/data/api/desktop_web_models.dart';

extension DesktopApiTraffic on DesktopApiClient {
  Future<List<DesktopClient>> clients() async =>
      desktopClients(await getData('/api/v1/clients'));

  Future<DesktopClientGroups> clientGroups() async =>
      DesktopClientGroups.fromJson(await getJson('/api/v1/clients/groups'));

  Future<void> configureClientGroups({
    required bool enabled,
    required List<DesktopClientGroup> groups,
  }) => postAction(
    '/api/v1/clients/groups',
    body: {
      'enabled': enabled,
      'groups': [for (final group in groups) group.toJson()],
    },
  );

  Future<DesktopClientLimits> clientLimits() async =>
      DesktopClientLimits.fromJson(await getJson('/api/v1/status'));

  Future<void> configureClientAlias({
    required String ip,
    required String name,
  }) => postAction('/api/v1/clients/alias', body: {'ip': ip, 'name': name});

  Future<void> configureAccess({
    required List<String> allowedClients,
    required List<String> blockedClients,
  }) => postAction(
    '/api/v1/dns/access/configure',
    body: {
      'allowedClients': allowedClients,
      'blockedClients': blockedClients,
    },
  );

  Future<void> configureRateLimit(Map<String, Object?> config) =>
      postAction('/api/v1/dns/ratelimit/configure', body: config);

  Future<DesktopRuleCheckResult> checkRule({
    required String domain,
    required String qtype,
  }) async => DesktopRuleCheckResult.fromJson(
    await postJson(
      '/api/v1/filter/check',
      body: {'domain': domain, 'qtype': qtype},
    ),
  );

  Future<DesktopWebStatus> webStatus() async =>
      DesktopWebStatus.fromJson(await getJson('/api/v1/web/status'));

  Future<void> configureWeb({required bool enabled, required int port}) => postAction(
    '/api/v1/web/configure',
    body: {'enabled': enabled, 'port': port, 'configureFirewall': true},
  );

  Future<void> configureWebFirewall(bool allowed) =>
      postAction('/api/v1/web/firewall', body: {'enable': allowed});

  Future<void> setupAdmin({
    required String username,
    required String password,
  }) => postAction(
    '/api/v1/auth/setup',
    body: {'username': username, 'password': password},
  );

  Future<void> changeAdminPassword({
    required String username,
    required String oldPassword,
    required String newPassword,
  }) => postAction(
    '/api/v1/auth/password',
    body: {
      'username': username,
      'oldPassword': oldPassword,
      'newPassword': newPassword,
    },
  );

  Future<DesktopPortCheck> portCheck() async =>
      DesktopPortCheck.fromJson(await getJson('/api/v1/portcheck'));

  Future<DesktopPortCheck> autofixPort() async =>
      DesktopPortCheck.fromJson(
        await postJson(
          '/api/v1/portcheck/autofix',
          body: {'startDNS': false},
        ),
      );

}
