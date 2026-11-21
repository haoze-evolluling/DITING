import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/state/feature_hub_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 简洁模式默认隐藏的三类卡片，直接由分类清单推导，避免测试里再抄一份键名。
Set<String> _expectedSimpleDefaults() => hiddenKeysOfCategories(
  simpleModeHiddenCategoryIds,
  l10n: lookupAppL10n(const Locale('zh')),
);

void main() {
  late MemoryLegacyPrefsStore store;

  setUp(() => store = MemoryLegacyPrefsStore());

  ProviderContainer container({AppWorkMode mode = AppWorkMode.normal}) {
    final instance = ProviderContainer(
      overrides: [
        legacyPrefsStoreProvider.overrideWithValue(store),
        workModeProvider.overrideWith(() => _Mode(mode)),
      ],
    );
    addTearDown(instance.dispose);
    return instance;
  }

  test('普通模式默认不隐藏任何卡片，也不写简洁模式的键', () {
    final hidden = container().read(hiddenFeatureKeysProvider);
    expect(hidden, isEmpty);
    expect(
      store.read(hiddenFeaturesContainer, simpleModeHiddenFeaturesKey),
      isNull,
    );
  });

  test('简洁模式默认隐藏应用与网络、高级与诊断、数据与维护', () {
    final hidden = container(mode: AppWorkMode.express)
        .read(hiddenFeatureKeysProvider);
    expect(hidden, _expectedSimpleDefaults());
    expect(hidden, hasLength(14));
    final l10n = lookupAppL10n(const Locale('zh'));
    final visible = visibleFeatureCategories(hiddenKeys: hidden, l10n: l10n);
    expect(visible.map((category) => category.id), [
      FeatureCategoryId.dns,
      FeatureCategoryId.rules,
      FeatureCategoryId.interface_,
    ]);
    expect(
      store.read(hiddenFeaturesContainer, simpleModeHiddenFeaturesKey),
      _expectedSimpleDefaults().toList(),
    );
    expect(
      store.read(hiddenFeaturesContainer, hiddenFeaturesKey),
      isNull,
      reason: '简洁模式的默认值不应写到普通模式的键上',
    );
  });

  test('两种模式的隐藏集合互不影响', () {
    final simple = container(mode: AppWorkMode.express);
    simple
        .read(hiddenFeatureKeysProvider.notifier)
        .setVisible('provider_management', false);
    expect(
      simple.read(hiddenFeatureKeysProvider),
      contains('provider_management'),
    );

    final normal = container();
    expect(normal.read(hiddenFeatureKeysProvider), isEmpty);
  });

  test('升级迁移只执行一次：用户恢复后不再被默认值覆盖', () {
    final simple = container(mode: AppWorkMode.express);
    expect(simple.read(hiddenFeatureKeysProvider), _expectedSimpleDefaults());
    simple.read(hiddenFeatureKeysProvider.notifier).resetAll();
    expect(simple.read(hiddenFeatureKeysProvider), isEmpty);

    final reopened = container(mode: AppWorkMode.express);
    expect(
      reopened.read(hiddenFeatureKeysProvider),
      isEmpty,
      reason: '迁移标记已置位，重建容器不应重新隐藏三类卡片',
    );
  });

  test('迁移与用户已有隐藏项取并集', () {
    store.putStringSet(hiddenFeaturesContainer, simpleModeHiddenFeaturesKey, {
      'appearance',
    });
    final hidden = container(mode: AppWorkMode.express)
        .read(hiddenFeatureKeysProvider);
    expect(hidden, {..._expectedSimpleDefaults(), 'appearance'});
  });

  test('隐藏集合按当前模式读取，切模式即切换视图', () {
    final instance = ProviderContainer(
      overrides: [
        legacyPrefsStoreProvider.overrideWithValue(store),
        workModeProvider.overrideWith(() => _SwitchableMode()),
      ],
    );
    addTearDown(instance.dispose);
    final mode = instance.read(workModeProvider.notifier) as _SwitchableMode;

    expect(instance.read(hiddenFeatureKeysProvider), isEmpty);
    mode.switchTo(AppWorkMode.express);
    expect(instance.read(hiddenFeatureKeysProvider), _expectedSimpleDefaults());
    mode.switchTo(AppWorkMode.normal);
    expect(instance.read(hiddenFeatureKeysProvider), isEmpty);
  });
}

class _Mode extends WorkModeNotifier {
  _Mode(this.mode);

  final AppWorkMode mode;

  @override
  AppWorkMode build() => mode;
}

class _SwitchableMode extends WorkModeNotifier {
  @override
  AppWorkMode build() => AppWorkMode.normal;

  void switchTo(AppWorkMode mode) => state = mode;
}
