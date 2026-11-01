/// The settings branch's service page: where the app connects, and what the host service reports.
///
/// The old desktop console's `ServicePanel.vue` is the functional blueprint. The connection half is
/// editable because it is the app's own configuration; the core-service half is read-only because
/// the HTTP API only exposes its status.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/pages/settings/widgets/core_service_card.dart';
import 'package:diting/desktop/pages/settings/widgets/service_connection_card.dart';
import 'package:diting/desktop/widgets/desktop_card_board.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:material_ui/material_ui.dart';

class DesktopServicePage extends StatelessWidget {
  const DesktopServicePage({super.key});

  static const path = '/settings/service';

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
