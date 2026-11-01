/// Client, group, tool and LAN-console endpoints, split out of [DesktopApiClient] to keep every file
/// inside the project's size budget. The transport helpers it calls are documented there.
library;

import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:diting/desktop/data/api/desktop_client_groups_models.dart';
import 'package:diting/desktop/data/api/desktop_rule_check_models.dart';
import 'package:diting/desktop/data/api/desktop_tools_models.dart';
import 'package:diting/desktop/data/api/desktop_traffic_models.dart';
import 'package:diting/desktop/data/api/desktop_web_models.dart';

extension DesktopApiTraffic on DesktopApiClient {
  /// The clients the service has seen, in its own order.
  Future<List<DesktopClient>> clients() async =>
      desktopClients(await getData('/api/v1/clients'));

  Future<DesktopClientGroups> clientGroups() async =>
      DesktopClientGroups.fromJson(await getJson('/api/v1/clients/groups'));

  /// The service drops groups without members and normalises the rest, so the caller re-reads.
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

  /// The ACL and rate-limit blocks live inside `/status`; there is no dedicated read endpoint.
  Future<DesktopClientLimits> clientLimits() async =>
      DesktopClientLimits.fromJson(await getJson('/api/v1/status'));

  /// An empty [name] clears the alias.
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

  /// Simulates one lookup against the loaded rules. `qtype` is the DNS type name, e.g. `A`.
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

  /// The service decides the listen address and whether a firewall rule is needed.
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

  /// Opens and closes the DNS port to see whether it can be taken; on demand only.
  Future<DesktopPortCheck> portCheck() async =>
      DesktopPortCheck.fromJson(await getJson('/api/v1/portcheck'));

  /// Stops the system listener the service knows about (ICS / resolved stub) and re-probes.
  /// `startDNS` stays false: the old console fixed the port without starting the listener.
  Future<DesktopPortCheck> autofixPort() async =>
      DesktopPortCheck.fromJson(
        await postJson(
          '/api/v1/portcheck/autofix',
          body: {'startDNS': false},
        ),
      );

}
