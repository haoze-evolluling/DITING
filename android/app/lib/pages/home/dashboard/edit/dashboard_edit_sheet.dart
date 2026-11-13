import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/dashboard_models.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Tapping appends the card at the end and closes, so no disabled state is needed.
class DashboardEditSheet extends ConsumerWidget {
  const DashboardEditSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final widgets = ref.watch(dashboardWidgetsProvider);
    final notifier = ref.read(dashboardWidgetsProvider.notifier);
    final available = [
      for (final widget in DashboardWidget.values)
        if (!widgets.contains(widget)) widget,
    ];
    return CommonScaffold(
      title: context.l10n.dashboardAddCard,
      actions: [
        TextButton(
          onPressed: () => notifier.reset(),
          child: Text(context.l10n.dashboardRestoreDefaults),
        ),
      ],
      body: available.isEmpty
          ? AppBarClearance(
              child: Center(
                child: NullStatus(
                  illustration: NullStatusIllustration.data,
                  label: context.l10n.dashboardAllCardsAdded,
                  description: context.l10n.dashboardAllCardsAddedDescription,
                ),
              ),
            )
          : ListView(
              // The sheet title floats over the body, so this top padding is required.
              padding: EdgeInsets.only(
                top: context.contentTopPadding,
                bottom: 24,
              ),
              children: [
                ListHeader(title: context.l10n.dashboardAvailableCards),
                for (final widget in available)
                  ListItem(
                    leading: GlyphIcon(_glyphOf(widget)),
                    title: Text(widget.label(context.l10n)),
                    subtitle: Text(_descriptionOf(widget, context.l10n)),
                    trailing: const GlyphIcon(AppGlyphs.addCircle, size: 20),
                    onTap: () {
                      notifier.add(widget);
                      Navigator.of(context).maybePop();
                    },
                  ),
                ListFooter(text: context.l10n.dashboardOrderHint),
              ],
            ),
    );
  }

  static Glyph _glyphOf(DashboardWidget widget) => switch (widget) {
    DashboardWidget.provider => AppGlyphs.dns,
    DashboardWidget.resolution => AppGlyphs.shuffle,
    DashboardWidget.status => AppGlyphs.status,
    DashboardWidget.networkSpeed => AppGlyphs.speed,
    DashboardWidget.siteLatency => AppGlyphs.target,
    DashboardWidget.memoryInfo => AppGlyphs.memory,
    DashboardWidget.intranetIp => AppGlyphs.devices,
  };

  static String _descriptionOf(DashboardWidget widget, AppL10n l10n) =>
      switch (widget) {
        DashboardWidget.provider => l10n.dashboardCardProviderDescription,
        DashboardWidget.resolution => l10n.dashboardCardResolutionDescription,
        DashboardWidget.status => l10n.dashboardCardStatusDescription,
        DashboardWidget.networkSpeed => l10n.dashboardCardSpeedDescription,
        DashboardWidget.siteLatency => l10n.dashboardCardSiteLatencyDescription,
        DashboardWidget.memoryInfo => l10n.dashboardCardMemoryDescription,
        DashboardWidget.intranetIp => l10n.dashboardCardIntranetDescription,
      };
}
