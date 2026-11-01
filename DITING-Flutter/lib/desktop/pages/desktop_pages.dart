/// The two desktop branches that are still placeholders.
///
/// They are rebuilt here rather than imported from `lib/pages` because those pages own Android
/// data sources (native channels, sqflite, VPN providers). Their functionality is not invented
/// either: each branch maps onto the old desktop console's pages (`Desktop/frontend/src`), which
/// is the functional blueprint. What must not be rebuilt is the look: a [CommonScaffold] with the
/// same localized title as Android, and a [NullStatus] empty state placed like Android's own
/// full-page empty states (`AppBarClearance` + `Center`), so a tall desktop window does not leave
/// the block stranded at the top. Until a branch's data layer lands (step 4 of
/// `docs/development/flutter-desktop-ui.md`), it states that plainly instead of showing invented
/// values. Home is not listed here: it has its own dashboard board (see
/// `home/desktop_home_page.dart`), and logs has its own page (see `logs/desktop_logs_page.dart`).
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

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
    body: _CenteredEmptyState(
      status: NullStatus(
        label: context.l10n.unknownRouteBody,
        description: location,
        illustration: NullStatusIllustration.search,
      ),
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
    body: _CenteredEmptyState(
      status: NullStatus(
        label: context.l10n.commonPendingTitle,
        description: context.l10n.commonPendingBody,
        illustration: illustration,
      ),
    ),
  );
}

/// Full-page empty state: centered, but still scrollable so enlarged text cannot overflow, with
/// room reserved for the floating app bar. Same arrangement as `UnknownRoutePage` on Android.
class _CenteredEmptyState extends StatelessWidget {
  const _CenteredEmptyState({required this.status});

  final Widget status;

  @override
  Widget build(BuildContext context) => AppBarClearance(
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: status,
      ),
    ),
  );
}
