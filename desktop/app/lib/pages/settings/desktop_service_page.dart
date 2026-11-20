library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/pages/settings/widgets/core_service_card.dart';
import 'package:diting_desktop/pages/settings/widgets/service_connection_card.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:material_ui/material_ui.dart';

class DesktopServicePage extends StatelessWidget {
  const DesktopServicePage({super.key});

  static const path = '/hub/service';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CommonScaffold(
      title: l10n.desktopServicePageTitle,
      body: const PageBody(
        children: [
          DesktopCardBoard(cards: [ServiceConnectionCard(), CoreServiceCard()]),
        ],
      ),
    );
  }
}
