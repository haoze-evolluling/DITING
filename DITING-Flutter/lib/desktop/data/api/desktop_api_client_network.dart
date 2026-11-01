/// The adapter takeover API and the LAN DNS API, split out of `desktop_api_client.dart` so that file
/// stays inside the line budget.
///
/// Same client, same transport, same connection settings: these are extension methods, not a second
/// stack. Pages never call them directly; the providers in `desktop_adapters_providers.dart` and
/// `desktop_lan_providers.dart` do.
library;

import 'package:diting/desktop/data/api/desktop_adapters_models.dart';
import 'package:diting/desktop/data/api/desktop_api_client.dart';
import 'package:diting/desktop/data/api/desktop_lan_models.dart';

extension DesktopNetworkApi on DesktopApiClient {
  /// Only adapters the host considers usable: the service has already dropped virtual and
  /// disconnected ones, so the page does not filter the list again.
  Future<List<DesktopAdapter>> adapters() async {
    final data = await getData('/api/v1/adapters');
    final rows = data is List ? data : const [];
    return [
      for (final row in rows)
        if (row is Map) DesktopAdapter.fromJson(row.cast<String, Object?>()),
    ];
  }

  /// One adapter in or out of the takeover; the service keeps the pre-takeover DNS for the restore.
  Future<void> setAdapterTakeover(String adapterId, bool enable) => postAction(
    '/api/v1/takeover/adapter',
    body: {'adapterId': adapterId, 'enable': enable},
  );

  Future<DesktopLanStatus> lanStatus() async =>
      DesktopLanStatus.fromJson(await getJson('/api/v1/dns/lan'));

  /// Turning the service on also asks for the firewall rule, as the console did; whether the host
  /// actually has a firewall manager is the service's answer, not a guess here.
  Future<void> configureLan({
    required bool allowLan,
    bool configureFirewall = false,
  }) => postAction(
    '/api/v1/dns/lan/configure',
    body: {'allowLAN': allowLan, 'configureFirewall': configureFirewall},
  );

  Future<void> configureLanFirewall(bool enable) => postAction(
    '/api/v1/dns/lan/firewall',
    body: {'enable': enable},
  );
}
