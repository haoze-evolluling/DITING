library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const hiddenFeaturesContainer = LegacySettings.uiContainer;

/// 普通模式（以及服务器模式）的隐藏集合，沿用历史键名。
const hiddenFeaturesKey = 'hidden_features_set';

/// 简洁模式的隐藏集合：与普通模式各存一份，互不影响。
const simpleModeHiddenFeaturesKey = 'hidden_features_set_simple';

/// 简洁模式默认隐藏值的写入标记。
///
/// 键不存在表示「还没给这个模式写过默认值」：新装与升级安装都会命中，
/// 保证升级后也执行一次；写入后即置位，之后用户手动恢复的卡片不会再被覆盖。
const simpleModeHiddenSeededKey = 'hidden_features_simple_defaults_seeded';

/// 按工作模式选择隐藏集合所在的键。
///
/// 服务器模式没有功能中心（走独立的服务器中心），回落到普通模式的键即可。
String hiddenFeaturesKeyFor(AppWorkMode mode) => mode == AppWorkMode.express
    ? simpleModeHiddenFeaturesKey
    : hiddenFeaturesKey;

class HiddenFeatureKeysNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(legacySettingsRevisionProvider);
    final mode = ref.watch(workModeProvider);
    final store = ref.watch(legacyPrefsStoreProvider);
    final stored = _read(store, hiddenFeaturesKeyFor(mode)) ?? const {};
    if (mode != AppWorkMode.express) return stored;
    return _seedSimpleModeDefaults(store, stored);
  }

  void setVisible(String key, bool visible) {
    final next = {...state};
    if (visible) {
      next.remove(key);
    } else {
      next.add(key);
    }
    _write(next);
  }

  void toggle(String key) => setVisible(key, !state.contains(key));

  void resetAll() => _write(const {});

  /// 首次使用简洁模式时写入默认隐藏的分类。
  ///
  /// 与已有内容取并集：用户此前手动隐藏的卡片保持隐藏，默认隐藏的三类一并加入。
  Set<String> _seedSimpleModeDefaults(
    LegacyPrefsStore store,
    Set<String> stored,
  ) {
    final seeded = store.read(
      hiddenFeaturesContainer,
      simpleModeHiddenSeededKey,
    );
    if (seeded == true) return stored;
    final next = {
      ...stored,
      ...hiddenKeysOfCategories(simpleModeHiddenCategoryIds, l10n: currentL10n),
    };
    store.putStringSet(
      hiddenFeaturesContainer,
      simpleModeHiddenFeaturesKey,
      next,
    );
    store.putBool(hiddenFeaturesContainer, simpleModeHiddenSeededKey, true);
    return next;
  }

  Set<String>? _read(LegacyPrefsStore store, String key) {
    final value = store.read(hiddenFeaturesContainer, key);
    if (value is! List) return null;
    return {
      for (final item in value)
        if (item is String && item.isNotEmpty) item,
    };
  }

  void _write(Set<String> next) {
    ref
        .read(legacyPrefsStoreProvider)
        .putStringSet(
          hiddenFeaturesContainer,
          hiddenFeaturesKeyFor(ref.read(workModeProvider)),
          next,
        );
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }
}

final hiddenFeatureKeysProvider =
    NotifierProvider<HiddenFeatureKeysNotifier, Set<String>>(
      HiddenFeatureKeysNotifier.new,
    );

final visibleFeatureCategoriesProvider =
    Provider.family<List<MockFeatureCategory>, AppL10n>((ref, l10n) {
      final hidden = ref.watch(hiddenFeatureKeysProvider);
      return visibleFeatureCategories(hiddenKeys: hidden, l10n: l10n);
    });

class LogLongPressHintNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void acknowledge() => state = false;
}

final logLongPressHintProvider =
    NotifierProvider<LogLongPressHintNotifier, bool>(
      LogLongPressHintNotifier.new,
    );
