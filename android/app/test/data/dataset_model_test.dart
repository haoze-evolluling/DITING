import 'package:diting_android/data/db/datasets.dart';
import 'package:diting_android/data/db/storage_contract.dart';
import 'package:diting_android/data/db/rule_dataset_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/data/prefs/legacy_prefs_store.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/appearance_providers.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer container({String workMode = 'normal'}) {
    final c = ProviderContainer(
      overrides: [
        legacyPrefsStoreProvider.overrideWithValue(
          MemoryLegacyPrefsStore({
            'diting_settings': {'app_work_mode': workMode},
            'dns_vpn_prefs': const {},
            'diting_express_prefs': const {},
          }),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('数据集映射', () {
    test('普通模式使用独立的规则库与日志库', () {
      final dataSet = DataSet.fromWorkModeValue('normal');
      expect(dataSet, DataSet.normal);
      expect(dataSet.prefsContainer, LegacySettings.uiContainer);
      expect(dataSet.ruleDatabase, StorageContract.normalRulesDatabase);
      expect(dataSet.logsDatabase, StorageContract.normalLogsDatabase);
    });

    test('简洁模式使用独立的规则库与日志库', () {
      final dataSet = DataSet.fromWorkModeValue('express');
      expect(dataSet, DataSet.express);
      expect(dataSet.prefsContainer, LegacySettings.expressContainer);
      expect(dataSet.ruleDatabase, StorageContract.expressRulesDatabase);
      expect(dataSet.logsDatabase, StorageContract.expressLogsDatabase);
    });

    test('两种模式的库名互不相同', () {
      final files = {
        for (final dataSet in DataSet.values) ...[
          dataSet.ruleDatabase,
          dataSet.logsDatabase,
        ],
      };
      expect(files, hasLength(4));
    });

    test('provider 跟随工作模式切换数据库', () {
      final c = container();
      expect(c.read(activeRuleDatabaseProvider), StorageContract.normalRulesDatabase);
      expect(
        c.read(activeLogDatabaseFileProvider),
        StorageContract.normalLogsDatabase,
      );

      c.read(workModeProvider.notifier).select(AppWorkMode.express);
      expect(
        c.read(activeRuleDatabaseProvider),
        StorageContract.expressRulesDatabase,
      );
      expect(
        c.read(activeLogDatabaseFileProvider),
        StorageContract.expressLogsDatabase,
      );
      expect(
        c.read(subscriptionDatabaseFileProvider),
        StorageContract.expressRulesDatabase,
      );
    });
  });

  group('设置视图跟随工作模式', () {
    test('简洁模式下解析模式写进 diting_express_prefs', () {
      final c = container(workMode: 'express');
      expect(
        c.read(legacySettingsProvider).dnsContainer,
        LegacySettings.expressContainer,
      );

      c.read(resolutionModeProvider.notifier).select(ResolutionMode.smart);

      final store = c.read(legacyPrefsStoreProvider);
      expect(
        store.read(LegacySettings.expressContainer, 'dns_resolution_mode'),
        'smart_prediction',
      );
      expect(
        store.read(LegacySettings.uiContainer, 'dns_resolution_mode'),
        isNull,
      );
    });

    test('普通模式的 UI 键仍然全局，不因模式而分家', () {
      final c = container(workMode: 'express');
      final settings = c.read(legacySettingsProvider);
      settings.setThemeModeRaw('dark');
      expect(
        c
            .read(legacyPrefsStoreProvider)
            .read(LegacySettings.uiContainer, 'app_theme_mode'),
        'dark',
      );
    });

    test('切换工作模式后设置视图与规则库一起切换', () {
      final c = container();
      expect(c.read(activeDataSetProvider), DataSet.normal);
      expect(c.read(activeRuleDatabaseProvider), StorageContract.normalRulesDatabase);

      c.read(workModeProvider.notifier).select(AppWorkMode.express);

      expect(c.read(workModeProvider), AppWorkMode.express);
      expect(c.read(activeDataSetProvider), DataSet.express);
      expect(
        c.read(legacySettingsProvider).dnsContainer,
        LegacySettings.expressContainer,
      );
      expect(
        c.read(activeRuleDatabaseProvider),
        StorageContract.expressRulesDatabase,
      );
    });

    test('切回普通模式恢复普通数据集', () {
      final c = container(workMode: 'express');
      c.read(workModeProvider.notifier).select(AppWorkMode.normal);
      expect(c.read(activeDataSetProvider), DataSet.normal);
      expect(
        c.read(legacySettingsProvider).dnsContainer,
        LegacySettings.uiContainer,
      );
      expect(c.read(activeRuleDatabaseProvider), StorageContract.normalRulesDatabase);
    });
  });
}
