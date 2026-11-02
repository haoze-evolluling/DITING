import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/log_dashboard_widgets.dart';
import 'package:diting_android/pages/home/dashboard/dashboard_board.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/pages/logs/log_dashboard_cards.dart';
import 'package:diting_android/state/hub_settings_providers.dart';
import 'package:diting_android/state/log_dashboard_layout_providers.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Log dashboard board for one log mode: a plain column in view mode; drag handles, remove
/// badges and an add row in edit mode. Mirrors the home board so both behave the same.
class LogDashboardBoard extends ConsumerWidget {
  const LogDashboardBoard({super.key, required this.mode});

  final LegacyLogMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final widgets = ref.watch(visibleLogDashboardWidgetsProvider(mode));
    final editing = ref.watch(logDashboardEditingProvider);
    final side = dashboardMobileSideOf(MediaQuery.sizeOf(context).width);
    final Widget body;
    if (editing) {
      body = _EditingBoard(mode: mode, widgets: widgets);
    } else if (widgets.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.only(top: 40),
        child: NullStatus(
          illustration: NullStatusIllustration.data,
          label: context.l10n.dashboardEmptyLabel,
          description: context.l10n.dashboardEmptyDescription,
          action: FilledButton.tonal(
            onPressed: () =>
                ref.read(logDashboardEditingProvider.notifier).enter(),
            child: Text(context.l10n.dashboardEnterEditMode),
          ),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: dashboardCardGap,
        children: [
          for (final widget in widgets)
            KeyedSubtree(
              key: ValueKey(widget),
              child: buildLogDashboardCard(context, widget, mode),
            ),
        ],
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: side),
      child: body,
    );
  }
}

class _EditingBoard extends ConsumerWidget {
  const _EditingBoard({required this.mode, required this.widgets});

  final LegacyLogMode mode;
  final List<LogDashboardWidget> widgets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final notifier = ref.read(logDashboardWidgetsProvider(mode).notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: dashboardCardGap,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: ShapeDecoration(
            color: colorScheme.primaryContainer,
            shape: AppShape.all(AppCorner.md),
          ),
          child: Text(
            context.l10n.logDashboardEditHint(mode.label(context.l10n)),
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(color: colorScheme.onPrimaryContainer),
          ),
        ),
        if (widgets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: NullStatus(
              illustration: NullStatusIllustration.data,
              label: context.l10n.dashboardAllRemovedLabel,
              description: context.l10n.dashboardAllRemovedDescription,
            ),
          )
        else
          ReorderableListView.builder(
            // The page already scrolls; a nested scrollable would steal drag gestures.
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: widgets.length,
            onReorderItem: (oldIndex, newIndex) =>
                notifier.moveVisible(widgets, oldIndex, newIndex),
            proxyDecorator: (child, index, animation) => Material(
              color: Colors.transparent,
              child: ScaleTransition(
                scale: Tween(begin: 1.0, end: 1.02).animate(animation),
                child: child,
              ),
            ),
            itemBuilder: (context, index) {
              final widget = widgets[index];
              return Padding(
                key: ValueKey(widget),
                padding: const EdgeInsets.only(bottom: 12),
                child: DashboardEditBar(
                  bar: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const DashboardDragBadge(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.label(context.l10n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DashboardText.label(context),
                        ),
                      ),
                      DashboardRemoveBadge(
                        onPressed: () => notifier.remove(widget),
                      ),
                    ],
                  ),
                  child: buildLogDashboardCard(
                    context,
                    widget,
                    mode,
                    interactive: false,
                  ),
                ),
              );
            },
          ),
        OutlinedButton.icon(
          onPressed: () => showSheet<void>(
            context: context,
            builder: (_) => LogDashboardAddSheet(mode: mode),
          ),
          icon: Icon(Icons.add, size: 18, color: colorScheme.primary),
          label: Text(context.l10n.dashboardAddCard),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }
}

/// Cards of this mode that are not on the board yet. Tapping appends one and closes.
class LogDashboardAddSheet extends ConsumerWidget {
  const LogDashboardAddSheet({super.key, required this.mode});

  final LegacyLogMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stored = ref.watch(logDashboardWidgetsProvider(mode));
    final showAi = ref.watch(agentKeyConfiguredProvider);
    final notifier = ref.read(logDashboardWidgetsProvider(mode).notifier);
    final available = [
      for (final widget in logDashboardCatalogOf(mode))
        if (!stored.contains(widget) &&
            (showAi || widget != LogDashboardWidget.aiInsight))
          widget,
    ];
    return CommonScaffold(
      title: context.l10n.dashboardAddCard,
      actions: [
        TextButton(
          onPressed: notifier.reset,
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
                    title: Text(widget.label(context.l10n)),
                    subtitle: Text(widget.description(context.l10n)),
                    trailing: const GlyphIcon(AppGlyphs.addCircle, size: 20),
                    onTap: () {
                      notifier.add(widget);
                      Navigator.of(context).maybePop();
                    },
                  ),
                ListFooter(text: context.l10n.logDashboardModeFooter),
              ],
            ),
    );
  }
}
