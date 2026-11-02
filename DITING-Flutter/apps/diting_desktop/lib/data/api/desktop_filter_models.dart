/// The rule engine's subscription lists and the counters the console shows above them.
///
/// `GET /api/v1/filter/lists` answers with a bare list; `GET /api/v1/filter/stats` carries the
/// counters. Writes are per-list: add, update (name/URL/enabled), delete and refresh.
library;

int _int(Object? value) => switch (value) {
  num() => value.toInt(),
  String() => int.tryParse(value) ?? 0,
  _ => 0,
};

bool _bool(Object? value) => value == true;

/// `core.FilterStats`, as `/filter/stats` reports it.
class DesktopFilterSummary {
  const DesktopFilterSummary({
    required this.enabled,
    required this.rules,
    required this.activeLists,
    required this.queries,
    required this.blocked,
    required this.allowed,
    required this.blockRate,
    required this.scheduleActive,
    required this.paused,
    required this.pausedRemaining,
  });

  static const empty = DesktopFilterSummary(
    enabled: false,
    rules: 0,
    activeLists: 0,
    queries: 0,
    blocked: 0,
    allowed: 0,
    blockRate: 0,
    scheduleActive: true,
    paused: false,
    pausedRemaining: Duration.zero,
  );

  factory DesktopFilterSummary.fromJson(Map<String, Object?> json) =>
      DesktopFilterSummary(
        enabled: _bool(json['enabled']),
        rules: _int(json['totalRules']),
        activeLists: _int(json['activeLists']),
        queries: _int(json['totalQueries']),
        blocked: _int(json['blockedQueries']),
        allowed: _int(json['allowedQueries']),
        blockRate: switch (json['blockRate']) {
          num() => (json['blockRate'] as num).toDouble(),
          String() => double.tryParse(json['blockRate'] as String) ?? 0,
          _ => 0,
        },
        scheduleActive: json['scheduleActive'] != false,
        paused: _bool(json['paused']),
        pausedRemaining: Duration(
          seconds: _int(json['pausedRemainingSec']),
        ),
      );

  final bool enabled;
  final int rules;
  final int activeLists;
  final int queries;
  final int blocked;
  final int allowed;

  /// 0..1, as the service computes it.
  final double blockRate;

  /// Whether the current instant is inside the time plan's window (always true when no plan is on).
  final bool scheduleActive;

  final bool paused;
  final Duration pausedRemaining;
}

/// One `core.FilterList`.
class DesktopFilterList {
  const DesktopFilterList({
    required this.id,
    required this.name,
    required this.url,
    required this.enabled,
    required this.rulesCount,
    required this.lastUpdated,
    required this.lastStatus,
    required this.lastError,
  });

  factory DesktopFilterList.fromJson(Map<String, Object?> json) {
    final updated = _int(json['lastUpdated']);
    return DesktopFilterList(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      url: '${json['url'] ?? ''}',
      enabled: _bool(json['enabled']),
      rulesCount: _int(json['rulesCount']),
      lastUpdated: updated > 0
          ? DateTime.fromMillisecondsSinceEpoch(updated).toLocal()
          : null,
      lastStatus: '${json['lastStatus'] ?? ''}',
      lastError: '${json['lastError'] ?? ''}',
    );
  }

  final String id;
  final String name;
  final String url;
  final bool enabled;
  final int rulesCount;
  final DateTime? lastUpdated;

  /// `ok` | `unchanged` | `cached` | `failed`; empty before the first pull.
  final String lastStatus;
  final String lastError;

  DesktopFilterList copyWith({bool? enabled}) => DesktopFilterList(
    id: id,
    name: name,
    url: url,
    enabled: enabled ?? this.enabled,
    rulesCount: rulesCount,
    lastUpdated: lastUpdated,
    lastStatus: lastStatus,
    lastError: lastError,
  );

  /// The update endpoint replaces name, URL and the switch; the counters stay the service's.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'enabled': enabled,
  };
}

/// The list page's answer: the total the service counted plus the rows themselves.
class DesktopFilterLists {
  const DesktopFilterLists({required this.total, required this.lists});

  factory DesktopFilterLists.fromJson(Map<String, Object?> json) =>
      DesktopFilterLists(
        total: _int(json['total']),
        lists: [
          for (final item in json['lists'] as List? ?? const [])
            if (item is Map)
              DesktopFilterList.fromJson(item.cast<String, Object?>()),
        ],
      );

  static const empty = DesktopFilterLists(total: 0, lists: []);

  final int total;
  final List<DesktopFilterList> lists;
}
