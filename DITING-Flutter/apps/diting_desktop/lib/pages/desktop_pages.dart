/// The unmatched-route page.
///
/// Every branch now has a real page, so the only thing left here is the fallback: it mirrors the
/// Android unknown-route page without importing it, because that page owns Android navigation.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

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
