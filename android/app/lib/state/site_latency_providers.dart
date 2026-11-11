/// Sites the dashboard's speed card shows, persisted by id so an app upgrade keeps the user's pick
/// and drops only sites that no longer exist.
library;

import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/site_latency_categories.dart';
import 'package:diting_android/data/site_latency_targets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

LegacySettings _settings(Ref ref) => ref.read(legacySettingsProvider);

final dashboardSiteIdsProvider =
    NotifierProvider<DashboardSiteIdsNotifier, List<String>>(
      DashboardSiteIdsNotifier.new,
    );

/// Where the card gets its four cells: the saved ids padded back to
/// [dashboardSiteCount] by the catalog, so a stale or short list never draws a gap.
final dashboardSitesProvider = Provider<List<SiteLatencyTarget>>(
  (ref) => resolveDashboardSites(ref.watch(dashboardSiteIdsProvider)),
);

class DashboardSiteIdsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => [
    for (final target in resolveDashboardSites(
      _settings(ref).dashboardSiteIds ?? defaultDashboardSiteIds,
    ))
      target.id,
  ];

  /// Adds or removes [id]. Returns false when the card is full, so the page can explain why the
  /// toggle did nothing; the last site can never be removed because an empty card has no meaning.
  bool toggle(String id) {
    if (!siteLatencyIds.contains(id)) {
      return false;
    }
    if (state.contains(id)) {
      if (state.length <= 1) {
        return false;
      }
      _commit([
        for (final item in state)
          if (item != id) item,
      ]);
      return true;
    }
    if (state.length >= dashboardSiteCount) {
      return false;
    }
    _commit([...state, id]);
    return true;
  }

  void reset() => _commit(List.of(defaultDashboardSiteIds));

  /// Updates the provider and the store together. The list may hold fewer than
  /// [dashboardSiteCount] entries — the card pads it at draw time — so removing a site always
  /// works instead of being undone by the padding.
  void _commit(List<String> next) {
    final unique = <String>[];
    for (final id in next) {
      if (siteLatencyIds.contains(id) && !unique.contains(id)) {
        unique.add(id);
      }
    }
    state = unique;
    _settings(ref).setDashboardSiteIds(unique);
  }
}
