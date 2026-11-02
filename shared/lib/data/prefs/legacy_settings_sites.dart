// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
part of 'legacy_settings.dart';

/// Which sites the dashboard's speed card draws. Null when the user never picked, so the built-in
/// four apply; unknown ids are dropped here and the catalog pads a short list back to four.
extension LegacySettingsSites on LegacySettings {
  List<String>? get dashboardSiteIds {
    final raw = _string(LegacySettings.uiContainer, 'dashboard_site_ids');
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return null;
      }
      final ids = <String>[];
      for (final item in decoded) {
        if (item is String && item.isNotEmpty && !ids.contains(item)) {
          ids.add(item);
        }
      }
      return ids.isEmpty ? null : ids;
    } on FormatException {
      return null;
    }
  }

  void setDashboardSiteIds(List<String> ids) {
    final unique = <String>[];
    for (final id in ids) {
      if (id.isNotEmpty && !unique.contains(id)) {
        unique.add(id);
      }
    }
    _store.putString(
      LegacySettings.uiContainer,
      'dashboard_site_ids',
      jsonEncode(unique),
    );
  }
}
