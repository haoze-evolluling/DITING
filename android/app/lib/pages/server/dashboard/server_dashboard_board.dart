import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/server_dashboard_widgets.dart';
import 'package:diting_android/pages/home/dashboard/dashboard_board.dart'
    show DashboardDragBadge, DashboardRemoveBadge;
import 'package:diting_android/pages/server/dashboard/server_dashboard_cards.dart';
import 'package:diting_android/state/server_dashboard_layout_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Server home dashboard board: a plain column in view mode; drag handles, remove badges and an
/// add row in edit mode. Mirrors the normal home and log boards so every dashboard behaves alike.
class ServerDashboardBoard extends ConsumerWidget {
  const ServerDashboardBoard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final widgets = ref.watch(serverDashboardWidgetsProvider);
    final editing = ref.watch(serverDashboardEditingProvider);
    final side = dashboardMobileSideOf(MediaQuery.sizeOf(context).width);
    final Widget body;
    if (editing) {
      body = _EditingBoard(widgets: widgets);
    } else if (widgets.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.only(top: 40),
        child: NullStatus(
          illustration: NullStatusIllustration.data,
          label: context.l10n.dashboardEmptyLabel,
          description: context.l10n.dashboardEmptyDescription,
          action: FilledButton.tonal(
            onPressed: () =>
                ref.read(serverDashboardEditingProvider.notifier).enter(),
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
            DashboardCardEntrance(
              key: ValueKey(widget),
              child: buildServerDashboardCard(context, widget),
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
  const _EditingBoard({required this.widgets});

  final List<ServerDashboardWidget> widgets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final notifier = ref.read(serverDashboardWidgetsProvider.notifier);
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
          child: Row(
            spacing: 8,
            children: [
              GlyphIcon(
                AppGlyphs.info,
                size: 16,
                color: colorScheme.onPrimaryContainer,
              ),
              Expanded(
                child: Text(
                  context.l10n.dashboardEditHint,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colorScheme.onPrimaryContainer),
                ),
              ),
            ],
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
                notifier.move(oldIndex, newIndex),
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
                  child: buildServerDashboardCard(
                    context,
                    widget,
                    interactive: false,
                  ),
                ),
              );
            },
          ),
        OutlinedButton.icon(
          onPressed: () => showSheet<void>(
            context: context,
            builder: (_) => const ServerDashboardAddSheet(),
          ),
          icon: GlyphIcon(AppGlyphs.add, size: 18, color: colorScheme.primary),
          label: Text(context.l10n.dashboardAddCard),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }
}

/// Cards that are not on the board yet. Tapping appends one and closes.
class ServerDashboardAddSheet extends ConsumerWidget {
  const ServerDashboardAddSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stored = ref.watch(serverDashboardWidgetsProvider);
    final notifier = ref.read(serverDashboardWidgetsProvider.notifier);
    final available = [
      for (final widget in ServerDashboardWidget.values)
        if (!stored.contains(widget)) widget,
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
                    leading: GlyphIcon(_glyphOf(widget)),
                    title: Text(widget.label(context.l10n)),
                    subtitle: Text(widget.description(context.l10n)),
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

  static Glyph _glyphOf(ServerDashboardWidget widget) => switch (widget) {
    ServerDashboardWidget.status => AppGlyphs.status,
    ServerDashboardWidget.upstream => AppGlyphs.dns,
    ServerDashboardWidget.lanAccess => AppGlyphs.devices,
    ServerDashboardWidget.cache => AppGlyphs.memory,
    ServerDashboardWidget.ruleControl => AppGlyphs.rules,
    ServerDashboardWidget.domainRules => AppGlyphs.verified,
  };
}
