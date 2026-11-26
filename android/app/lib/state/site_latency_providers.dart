library;

import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/data/site_latency_categories.dart';
import 'package:diting_android/data/site_latency_targets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

LegacySettings _settings(Ref ref) => ref.read(legacySettingsProvider);

final dashboardSiteIdsProvider =
    NotifierProvider<DashboardSiteIdsNotifier, List<String>>(
      DashboardSiteIdsNotifier.new,
    );

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

  void reset() => _commit(defaultDashboardSiteIds);

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
