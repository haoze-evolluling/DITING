library;

import 'package:diting_desktop/data/api/desktop_adapters_models.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_lan_models.dart';
import 'package:diting_desktop/data/api/desktop_tools_models.dart';

extension DesktopNetworkApi on DesktopApiClient {
  Future<List<DesktopAdapter>> adapters() async {
    final data = await getData('/api/v1/adapters');
    final rows = data is List ? data : const [];
    return [
      for (final row in rows)
        if (row is Map) DesktopAdapter.fromJson(row.cast<String, Object?>()),
    ];
  }

  Future<void> setAdapterTakeover(String adapterId, bool enable) => postAction(
    '/api/v1/takeover/adapter',
    body: {'adapterId': adapterId, 'enable': enable},
  );

  Future<DesktopLanStatus> lanStatus() async =>
      DesktopLanStatus.fromJson(await getJson('/api/v1/dns/lan'));

  Future<void> configureLan({
    required bool allowLan,
    bool configureFirewall = false,
  }) => postAction(
    '/api/v1/dns/lan/configure',
    body: {'allowLAN': allowLan, 'configureFirewall': configureFirewall},
  );

  Future<DesktopEmergencyRestore> emergencyRestore() async =>
      DesktopEmergencyRestore.fromJson(
        await postJson('/api/v1/takeover/emergency-restore'),
      );

  Future<void> configureLanFirewall(bool enable) => postAction(
    '/api/v1/dns/lan/firewall',
    body: {'enable': enable},
  );
}
