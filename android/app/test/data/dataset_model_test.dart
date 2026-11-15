// The data set model: one prefs container and one rule database per work mode, like the legacy
// `RuleDataset`. The UI, the engine config and the API all read the same one.

import 'package:diting_shared/data/db/datasets.dart';
import 'package:diting_shared/data/db/legacy_database.dart';
import 'package:diting_shared/data/db/legacy_schema.dart';
import 'package:diting_android/data/db/rule_dataset_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/state/appearance_providers.dart';
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
            'diting_dns_mode_prefs': const {},
          }),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('数据集映射', () {
    test('普通模式：dns_vpn_prefs + diting_database', () {
      final dataSet = DataSet.fromWorkModeValue('normal');
      expect(dataSet, DataSet.normal);
      expect(dataSet.prefsContainer, LegacySettings.uiContainer);
      expect(dataSet.ruleDatabase, LegacyDatabase.mainFile);
    });

    test('极速模式：diting_express_prefs + diting_express', () {
      final dataSet = DataSet.fromWorkModeValue('express');
      expect(dataSet, DataSet.express);
      expect(dataSet.prefsContainer, LegacySettings.expressContainer);
      expect(dataSet.ruleDatabase, LegacyDatabase.expressFile);
    });

    test('服务器模式沿用旧版 dns 值：diting_dns_mode_prefs + diting_dns_rules', () {
      final dataSet = DataSet.fromWorkModeValue('dns');
      expect(dataSet, DataSet.server);
      expect(dataSet.prefsContainer, LegacySettings.serverContainer);
      expect(dataSet.ruleDatabase, LegacyDatabase.serverFile);
    });

    test('服务器日志使用独立文件，不与普通/极速共享', () {
      final c = container();
      expect(c.read(activeLogDatabaseFileProvider), LegacyDatabase.mainFile);

      c.read(workModeProvider.notifier).select(AppWorkMode.express);
      expect(c.read(activeLogDatabaseFileProvider), LegacyDatabase.expressFile);

      c.read(workModeProvider.notifier).select(AppWorkMode.server);
      expect(
        c.read(activeLogDatabaseFileProvider),
        LegacyDatabase.serverLogFile,
      );
      expect(LegacyDatabase.serverLogFile, isNot(LegacyDatabase.mainFile));
      expect(LegacyDatabase.serverLogFile, isNot(LegacyDatabase.expressFile));

      final statements = LegacySchema.statementsFor(
        LegacyDatabase.serverLogFile,
      ).join('\n');
      expect(statements, contains('CREATE TABLE `dns_log`'));
      expect(statements, contains('CREATE TABLE `dns_cache`'));
      expect(statements, contains('CREATE TABLE `dns_race_log`'));
      expect(statements, contains('CREATE TABLE `bootstrap_log`'));
      expect(statements, isNot(contains('http_request_log')));
    });
  });

  group('设置视图跟随工作模式', () {
    test('极速模式下解析模式写进 diting_express_prefs', () {
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
      // `_ui` stays `dns_vpn_prefs`: the whole app shares one theme.
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
      expect(c.read(activeRuleDatabaseProvider), LegacyDatabase.mainFile);

      c.read(workModeProvider.notifier).select(AppWorkMode.express);

      expect(c.read(workModeProvider), AppWorkMode.express);
      expect(c.read(activeDataSetProvider), DataSet.express);
      expect(
        c.read(legacySettingsProvider).dnsContainer,
        LegacySettings.expressContainer,
      );
      expect(c.read(activeRuleDatabaseProvider), LegacyDatabase.expressFile);
      expect(
        c.read(subscriptionDatabaseFileProvider),
        LegacyDatabase.expressFile,
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
      expect(c.read(activeRuleDatabaseProvider), LegacyDatabase.mainFile);
    });

    test('服务器模式读写自己的数据集', () {
      final c = container(workMode: 'dns');
      expect(c.read(activeDataSetProvider), DataSet.server);
      expect(
        c.read(legacySettingsProvider).dnsContainer,
        LegacySettings.serverContainer,
      );
      expect(c.read(activeRuleDatabaseProvider), LegacyDatabase.serverFile);

      c.read(resolutionModeProvider.notifier).select(ResolutionMode.parallel);
      expect(
        c
            .read(legacyPrefsStoreProvider)
            .read(LegacySettings.serverContainer, 'dns_resolution_mode'),
        'parallel_race',
      );
    });
  });
}
