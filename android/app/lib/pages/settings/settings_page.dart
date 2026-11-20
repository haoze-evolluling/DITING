library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/router.dart';
import 'package:diting_android/routes/system_routes.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/nav_entry_row.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.l10n.hubOtherSettings,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.wrench,
          tooltip: context.l10n.devOptions,
          onPressed: () => context.push(SystemPaths.developer),
        ),
      ],
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.settingsRunSection,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.layers,
                title: context.l10n.workModeSettingTitle,
                subtitle: context.l10n.settingsModeSubtitle,
                onPressed: () => context.push(Routes.modeSelect),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.settingsSystemSection,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.language,
                title: context.l10n.languageTitle,
                subtitle: context.l10n.settingsLanguageSubtitle,
                onPressed: () => context.push(SystemPaths.language),
              ),
            ],
          ),
          generateSection(
            title: context.l10n.settingsGuideSection,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.info,
                title: context.l10n.workModeGuideTitle,
                subtitle: context.l10n.settingsWizardSubtitle,
                onPressed: () => context.push(Routes.modeOnboarding),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
