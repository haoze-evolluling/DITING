/// The parsed cleanup catalog returned by `rust/diting-cleanup-core`.
///
/// Every table list, source-table pair, WHERE clause, preference key and the `allData` order is read
/// from the kernel once; a missing section or action throws instead of falling back to an empty
/// cleanup that reports success without deleting anything.
library;

import 'package:diting_android/data/db/rust_cleanup_core.dart';

typedef CleanupRulePair = ({String table, String sourceTable});
typedef CleanupPrefEntry = ({String container, String key});

class CleanupPlan {
  CleanupPlan._(this._raw);

  static final CleanupPlan instance = CleanupPlan._(
    RustCleanupCore.instance.plan(),
  );

  final Map<String, Object?> _raw;

  Map<String, Object?> _section(String name) {
    final section = _raw[name];
    if (section is! Map) {
      throw StateError('cleanup core: missing "$name" section');
    }
    return section.cast<String, Object?>();
  }

  Map<String, Object?> _child(String section, String child) {
    final value = _section(section)[child];
    if (value is! Map) {
      throw StateError('cleanup core: missing "$section.$child"');
    }
    return value.cast<String, Object?>();
  }

  String _childString(String section, String child, String key) {
    final value = _child(section, child)[key];
    if (value is! String) {
      throw StateError('cleanup core: missing "$section.$child.$key"');
    }
    return value;
  }

  String _string(String section, String key) {
    final value = _section(section)[key];
    if (value is! String) {
      throw StateError('cleanup core: missing "$section.$key"');
    }
    return value;
  }

  bool _bool(String section, String key) {
    final value = _section(section)[key];
    if (value is! bool) {
      throw StateError('cleanup core: missing "$section.$key"');
    }
    return value;
  }

  List<String> _strings(String section, String key) {
    final value = _section(section)[key];
    if (value is! List) {
      throw StateError('cleanup core: missing "$section.$key"');
    }
    return [for (final item in value) item as String];
  }

  List<CleanupRulePair> _pairs(String section, String key) {
    final value = _section(section)[key];
    if (value is! List) {
      throw StateError('cleanup core: missing "$section.$key"');
    }
    return [
      for (final item in value)
        (
          table: (item as Map)['table'] as String,
          sourceTable: item['sourceTable'] as String,
        ),
    ];
  }

  Map<String, Object?> _action(String name) {
    final action = _section('actions')[name];
    if (action is! Map) {
      throw StateError('cleanup core: missing action "$name"');
    }
    return action.cast<String, Object?>();
  }

  bool exitsApp(String action) => _action(action)['exitsApp'] as bool;

  bool affectsEngine(String action) => _action(action)['affectsEngine'] as bool;

  List<String> get logTables => _strings('logs', 'tables');
  String get trafficTable => _string('traffic', 'table');
  String get dnsCacheTable => _string('dnsCache', 'table');

  List<String> get weightContainers => _strings('weights', 'containers');
  String get providerWeightsKey => _string('weights', 'providerKey');
  String get bootstrapWeightsKey => _string('weights', 'bootstrapKey');

  List<CleanupRulePair> get domainClearPairs =>
      _pairs('domainRules', 'clearPairs');
  String get domainRewriteTable => _string('domainRules', 'rewriteTable');
  String get domainRewriteSourceTable =>
      _string('domainRules', 'rewriteSourceTable');
  String get domainRewriteWhere => _string('domainRules', 'rewriteWhere');
  List<String> get domainCosmeticTables =>
      _strings('domainRules', 'cosmeticTables');
  String get domainSubscriptionTable =>
      _string('domainRules', 'subscriptionTable');
  String get domainSubscriptionWhere =>
      _string('domainRules', 'subscriptionWhere');
  String get subscriptionResetTable =>
      _childString('domainRules', 'subscriptionReset', 'table');
  Map<String, Object?> get subscriptionResetValues =>
      (_child('domainRules', 'subscriptionReset')['values'] as Map)
          .cast<String, Object?>();
  String get autoUpdateOrphanTable =>
      _childString('domainRules', 'autoUpdateOrphans', 'table');
  String get autoUpdateOrphanWhere =>
      _childString('domainRules', 'autoUpdateOrphans', 'where');
  bool get seedPresetOnMain => _bool('domainRules', 'seedPresetOnMain');

  List<CleanupRulePair> get addressClearPairs =>
      _pairs('addressRules', 'clearPairs');
  String get addressRewriteTable => _string('addressRules', 'rewriteTable');
  String get addressRewriteSourceTable =>
      _string('addressRules', 'rewriteSourceTable');
  String get addressRewriteWhere => _string('addressRules', 'rewriteWhere');

  List<String> get subscriptionTables => _strings('subscriptions', 'tables');
  List<CleanupRulePair> get subscriptionRulePairs =>
      _pairs('subscriptions', 'rulePairs');
  String get subscriptionSourceWhere => _string('subscriptions', 'sourceWhere');

  String get appRulesContainer => _string('appRules', 'container');
  List<String> get appRuleKeys => _strings('appRules', 'keys');
  String get httpsInspectionReadyKey => _string('appRules', 'readyKey');

  String get customBackgroundContainer =>
      _string('customBackground', 'container');
  List<String> get customBackgroundKeys => _strings('customBackground', 'keys');

  String get settingsGuidesContainer => _string('settingsGuides', 'container');
  List<String> get settingsGuideKeys => _strings('settingsGuides', 'keys');
  String get dismissedContainer =>
      _string('settingsGuides', 'dismissedContainer');
  String get dismissedPrefix => _string('settingsGuides', 'dismissedPrefix');

  List<String> get allDataOrder => _strings('allData', 'order');
  List<String> get allDataTables => _strings('allData', 'tables');
  List<CleanupPrefEntry> get allDataPrefs {
    final value = _section('allData')['prefs'];
    if (value is! List) {
      throw StateError('cleanup core: missing "allData.prefs"');
    }
    return [
      for (final item in value)
        (
          container: (item as Map)['container'] as String,
          key: item['key'] as String,
        ),
    ];
  }
}
