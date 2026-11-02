import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/dashboard_models.dart';
import 'package:diting_android/pages/home/dashboard/cards/intranet_ip_card.dart';
import 'package:diting_android/pages/home/dashboard/cards/memory_card.dart';
import 'package:diting_android/pages/home/dashboard/cards/network_speed_card.dart';
import 'package:diting_android/pages/home/dashboard/cards/provider_card.dart';
import 'package:diting_android/pages/home/dashboard/cards/resolution_card.dart';
import 'package:diting_android/pages/home/dashboard/cards/site_latency_card.dart';
import 'package:diting_android/pages/home/dashboard/cards/status_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/pages/home/dashboard/edit/dashboard_edit_sheet.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Where dashboard cards navigate to. One callback taking the card, so every card opens its own
/// second-level page instead of all of them sharing the request page; `null` means no detail
/// button (edit mode, or a card that has no drill-down page yet).
class DashboardCardActions {
  const DashboardCardActions({this.onOpenDetail});

  /// No targets (edit mode): no card shows a detail button.
  static const none = DashboardCardActions();

  final ValueChanged<DashboardWidget>? onOpenDetail;

  /// Detail callback for one card, or null when that card has no page.
  VoidCallback? detailOf(DashboardWidget widget) {
    final open = onOpenDetail;
    if (open == null) return null;
    return () => open(widget);
  }
}

/// Dashboard card registry. Each card owns a distinct second-level page, so the board shows five
/// different devices' worth of detail rather than five doors into the request list.
Widget buildDashboardCard(
  DashboardWidget widget,
  DashboardCardActions actions,
) {
  return switch (widget) {
    DashboardWidget.provider => const ProviderCard(),
    DashboardWidget.resolution => const ResolutionCard(),
    DashboardWidget.status => StatusCard(onDetail: actions.detailOf(widget)),
    DashboardWidget.networkSpeed => NetworkSpeedCard(
      onDetail: actions.detailOf(widget),
    ),
    DashboardWidget.siteLatency => SiteLatencyCard(
      onDetail: actions.detailOf(widget),
    ),
    DashboardWidget.memoryInfo => MemoryCard(
      onDetail: actions.detailOf(widget),
    ),
    DashboardWidget.intranetIp => IntranetIpCard(
      onDetail: actions.detailOf(widget),
    ),
  };
}

/// Dashboard card board: one column in dashboardWidgetsProvider order, plus a remove
/// badge, drag reordering and an add row in edit mode. Single column: Android has no room.
class DashboardBoard extends ConsumerWidget {
  const DashboardBoard({super.key, this.actions = DashboardCardActions.none});

  final DashboardCardActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final widgets = ref.watch(dashboardWidgetsProvider);
    final editing = ref.watch(dashboardEditingProvider);
    final side = dashboardMobileSideOf(MediaQuery.sizeOf(context).width);
    if (editing) {
      return _EditingBoard(widgets: widgets, side: side);
    }
    if (widgets.isEmpty) {
      return _EmptyBoard(side: side);
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: side),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: dashboardCardGap,
        children: [
          for (final widget in widgets)
            DashboardCardEntrance(
              key: ValueKey(widget),
              child: buildDashboardCard(widget, actions),
            ),
        ],
      ),
    );
  }
}

class _EmptyBoard extends ConsumerWidget {
  const _EmptyBoard({required this.side});

  final double side;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.fromLTRB(side, 40, side, 0),
      child: NullStatus(
        illustration: NullStatusIllustration.data,
        label: context.l10n.dashboardEmptyLabel,
        description: context.l10n.dashboardEmptyDescription,
        action: FilledButton.tonal(
          onPressed: () => ref.read(dashboardEditingProvider.notifier).enter(),
          child: Text(context.l10n.dashboardEnterEditMode),
        ),
      ),
    );
  }
}

class _EditingBoard extends ConsumerWidget {
  const _EditingBoard({required this.widgets, required this.side});

  final List<DashboardWidget> widgets;
  final double side;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: side),
      child: Column(
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
                Icon(
                  Icons.info_outline,
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
              // The outer scrollable already exists; nesting one would steal drag gestures.
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: widgets.length,
              onReorderItem: (oldIndex, newIndex) => ref
                  .read(dashboardWidgetsProvider.notifier)
                  .move(oldIndex, newIndex),
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
                  // Injected inside the card so the badge does not compete with the title and
                  // trailing action. The
                  // card dims the body only, keeping the bar at full color.
                  child: DashboardEditBar(
                    bar: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: const DashboardDragBadge(),
                        ),
                        const Spacer(),
                        DashboardRemoveBadge(
                          onPressed: () => ref
                              .read(dashboardWidgetsProvider.notifier)
                              .remove(widget),
                        ),
                      ],
                    ),
                    // No target in edit mode: navigating away mid-drag reads as a lost drag.
                    child: buildDashboardCard(
                      widget,
                      DashboardCardActions.none,
                    ),
                  ),
                );
              },
            ),
          _AddCardRow(side: 0),
        ],
      ),
    );
  }
}

/// Remove badge of an edit-mode card, shared by home and the log dashboard.
class DashboardRemoveBadge extends StatelessWidget {
  const DashboardRemoveBadge({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Material(
      color: colorScheme.errorContainer,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(
            Icons.close,
            size: 16,
            color: colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

/// Drag handle badge of an edit-mode card.
class DashboardDragBadge extends StatelessWidget {
  const DashboardDragBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 28,
        height: 28,
        child: GlyphIcon(
          AppGlyphs.dragHandle,
          size: 16,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AddCardRow extends ConsumerWidget {
  const _AddCardRow({required this.side});

  final double side;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: side),
      child: OutlinedButton.icon(
        onPressed: () => showSheet<void>(
          context: context,
          builder: (_) => const DashboardEditSheet(),
        ),
        icon: Icon(Icons.add, size: 18, color: colorScheme.primary),
        label: Text(context.l10n.dashboardAddCard),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
    );
  }
}
