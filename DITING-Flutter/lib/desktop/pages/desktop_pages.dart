/// The five desktop branches that are still placeholders.
///
/// They are rebuilt here rather than imported from `lib/pages` because those pages own Android
/// data sources (native channels, sqflite, VPN providers). What must not be rebuilt is the look:
/// every page is a [CommonScaffold] over a [PageBody], with the same localized titles as Android.
/// Until a branch's data layer lands (step 4 of `docs/development/flutter-desktop-ui.md`), it
/// states that plainly through [NullStatus] instead of showing invented values. Home is not
/// listed here: it already has its Android skeleton (see `home/desktop_home_page.dart`).
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:material_ui/material_ui.dart';

class DesktopFeatureHubPage extends StatelessWidget {
  const DesktopFeatureHubPage({super.key});

  @override
  Widget build(BuildContext context) => _PendingPage(
    title: context.l10n.bottomBarFeatureHub,
    illustration: NullStatusIllustration.apps,
  );
}

class DesktopLogsPage extends StatelessWidget {
  const DesktopLogsPage({super.key});

  @override
  Widget build(BuildContext context) => _PendingPage(
    title: context.l10n.logsDashboardTitle,
    illustration: NullStatusIllustration.logs,
  );
}

class DesktopTrafficPage extends StatelessWidget {
  const DesktopTrafficPage({super.key});

  @override
  Widget build(BuildContext context) => _PendingPage(
    title: context.l10n.trafficTitle,
    illustration: NullStatusIllustration.requests,
  );
}

class DesktopToolsPage extends StatelessWidget {
  const DesktopToolsPage({super.key});

  @override
  Widget build(BuildContext context) => _PendingPage(
    title: context.l10n.toolDiagnostics,
    illustration: NullStatusIllustration.wifi,
  );
}

class DesktopSettingsPage extends StatelessWidget {
  const DesktopSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => _PendingPage(
    title: context.l10n.hubOtherSettings,
    illustration: NullStatusIllustration.profile,
  );
}

/// Unmatched location; mirrors the Android fallback without importing its page.
class DesktopUnknownRoutePage extends StatelessWidget {
  const DesktopUnknownRoutePage({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) => CommonScaffold(
    title: context.l10n.unknownRouteTitle,
    body: PageBody(
      children: [
        NullStatus(
          label: context.l10n.unknownRouteBody,
          description: location,
          illustration: NullStatusIllustration.search,
        ),
      ],
    ),
  );
}

/// A branch that has no data source yet. Titles and empty states come from the shared ARB, so the
/// page reads like every other empty state in the app.
class _PendingPage extends StatelessWidget {
  const _PendingPage({required this.title, required this.illustration});

  final String title;
  final NullStatusIllustration illustration;

  @override
  Widget build(BuildContext context) => CommonScaffold(
    title: title,
    body: PageBody(
      children: [
        NullStatus(
          label: context.l10n.commonPendingTitle,
          description: context.l10n.commonPendingBody,
          illustration: illustration,
        ),
      ],
    ),
  );
}
