library;

import 'package:diting_desktop/pages/settings/widgets/appearance_options_card.dart';
import 'package:diting_desktop/pages/settings/widgets/appearance_preview_card.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:material_ui/material_ui.dart';

class AppearanceThemePane extends StatelessWidget {
  const AppearanceThemePane({super.key});

  static const _twoPaneMinWidth = 960.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _twoPaneMinWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: dashboardCardGap,
            children: [
              const AppearancePreviewCard(),
              Align(
                alignment: AlignmentDirectional.topStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: desktopSoloCardWidth,
                  ),
                  child: const AppearanceOptionsCard(),
                ),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: dashboardCardGap,
          children: const [
            Expanded(child: AppearancePreviewCard()),
            Expanded(child: AppearanceOptionsCard()),
          ],
        );
      },
    );
  }
}
