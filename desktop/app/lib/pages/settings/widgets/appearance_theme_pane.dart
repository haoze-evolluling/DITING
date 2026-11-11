/// The appearance page itself: the window preview on the left, the choices on the right.
///
/// This used to be one dashboard card holding a grid of phone thumbnails, which read as a mobile
/// settings screen transplanted into a window: nine postage stamps in a row, each one a phone. A
/// desktop reader compares a preview against the app they are looking at, so the preview is the
/// window and the choices sit beside it.
library;

import 'package:diting_desktop/pages/settings/widgets/appearance_options_card.dart';
import 'package:diting_desktop/pages/settings/widgets/appearance_preview_card.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:material_ui/material_ui.dart';

class AppearanceThemePane extends StatelessWidget {
  const AppearanceThemePane({super.key});

  /// Below this the two panes stack. The line is drawn where the palette gallery would drop to two
  /// columns — three tiles of a row are what keeps the nine palettes at three rows instead of five,
  /// and a preview beside a five-row gallery looked like an empty half-page.
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
        // An even split: the preview needs enough width to read as a window, and the gallery needs
        // enough to keep three tiles in a row on a 1280-wide window.
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
