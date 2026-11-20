library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/app/theme/colors.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ThemeColorPage extends ConsumerWidget {
  const ThemeColorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(paletteProvider);
    return CommonScaffold(
      title: context.l10n.appearancePaletteTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.appearancePaletteInfoLabel,
            items: [
              ListItem<AppPalette>.options(
                leading: const GlyphIcon(AppGlyphs.palette),
                title: Text(context.l10n.appearancePaletteTitle),
                value: palette,
                options: AppPalette.values,
                textBuilder: (value) => value.label(context.l10n),
                onChanged: (value) =>
                    ref.read(paletteProvider.notifier).select(value),
              ),
            ],
            footer: context.l10n.appearancePaletteBody,
          ),
        ],
      ),
    );
  }
}
