/// The hub branch: the desktop console's resolution and protection pages, presented as the app's
/// grouped feature list instead of the mobile card board.
///
/// Only entries whose page exists are listed. A card that opens a placeholder would promise work
/// the host cannot do, and the migration order in `docs/development/flutter-desktop-ui.md` adds the
/// remaining rows as their data layers land.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/pages/hub/desktop_upstream_page.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Keeps a desktop feature list readable instead of stretching a row across a 1920-wide window.
const double _contentMaxWidth = 880;

class DesktopFeatureHubPage extends StatelessWidget {
  const DesktopFeatureHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CommonScaffold(
      title: l10n.bottomBarFeatureHub,
      body: PageBody(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListHeader(title: l10n.desktopHubResolveSection),
                    generateGroup([
                      ListItem(
                        leading: const GlyphIcon(AppGlyphs.dns, size: 20),
                        title: Text(l10n.desktopHubUpstream),
                        subtitle: Text(l10n.desktopHubUpstreamBody),
                        trailing: const GlyphIcon(
                          AppGlyphs.chevronForward,
                          size: 18,
                        ),
                        onTap: () => context.push(DesktopUpstreamPage.path),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
