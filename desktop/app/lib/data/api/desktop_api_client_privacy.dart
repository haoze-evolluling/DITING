/// Privacy, safe search and safe browsing endpoints, split out of [DesktopApiClient] to keep every
/// file inside the project's size budget. The transport helpers it calls are documented there.
library;

import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_privacy_models.dart';

extension DesktopApiPrivacy on DesktopApiClient {
  Future<DesktopPrivacyConfig> privacyConfig() async =>
      DesktopPrivacyConfig.fromJson(await getJson('/api/v1/status'));

  Future<void> configurePrivacy(DesktopPrivacyConfig config) =>
      postAction('/api/v1/dns/privacy/configure', body: config.privacyJson());

  Future<void> configureUnqualified(bool enabled) => postAction(
    '/api/v1/dns/unqualified/configure',
    body: {'blockUnqualified': enabled},
  );

  Future<void> configureEcs(DesktopPrivacyConfig config) => postAction(
    '/api/v1/dns/ecs/configure',
    body: {
      'enabled': config.ecsEnabled,
      'stripECS': config.ecsStrip,
      'customSubnet': config.ecsCustomSubnet.trim(),
    },
  );

  Future<void> configureRebind(DesktopPrivacyConfig config) => postAction(
    '/api/v1/dns/rebind/configure',
    body: {
      'enabled': config.rebindEnabled,
      'allowedDomains': config.rebindAllowedDomains,
    },
  );

  Future<void> configureHosts(DesktopPrivacyConfig config) => postAction(
    '/api/v1/dns/hosts/configure',
    body: {
      'enabled': config.hostsEnabled,
      'useSystemHost': config.hostsUseSystem,
      'customFiles': config.hostsCustomFiles,
      'ttl': config.hostsTtl,
    },
  );

  Future<DesktopSafeSearchConfig> safeSearch() async =>
      DesktopSafeSearchConfig.fromJson(await getJson('/api/v1/safesearch/config'));

  /// The service merges the patch and answers with a success flag, so the page re-reads.
  Future<void> configureSafeSearch(Map<String, Object?> patch) =>
      postAction('/api/v1/safesearch/config', body: patch);

  Future<DesktopSafeBrowsing> safeBrowsing() async =>
      DesktopSafeBrowsing.fromJson(await getJson('/api/v1/filter/safebrowsing'));

  /// Answers with the normalised state (config + counters), which the page adopts directly.
  Future<DesktopSafeBrowsing> configureSafeBrowsing(
    Map<String, Object?> patch,
  ) async => DesktopSafeBrowsing.fromJson(
    await postJson('/api/v1/filter/safebrowsing', body: patch),
  );

}
