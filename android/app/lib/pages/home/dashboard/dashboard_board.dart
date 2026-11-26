import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/dashboard_models.dart';
import 'package:diting_android/pages/home/dashboard/cards/intranet_ip_card.dart';
import 'package:diting_android/pages/home/dashboard/cards/memory_card.dart';
import 'package:diting_android/pages/home/dashboard/cards/network_speed_card.dart';
import 'package:diting_android/pages/home/dashboard/cards/provider_card.dart';
import 'package:diting_android/pages/home/dashboard/cards/resolution_card.dart';
import 'package:diting_android/pages/home/dashboard/cards/site_latency_card.dart';
import 'package:diting_android/pages/home/dashboard/cards/status_card.dart';
import 'package:diting_android/widgets/dashboard/dashboard_card.dart';
import 'package:diting_android/widgets/dashboard/dashboard_density.dart';
import 'package:diting_android/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/pages/home/dashboard/edit/dashboard_edit_sheet.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/widgets/notice.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DashboardCardActions {
  const DashboardCardActions({this.onOpenDetail});

  static const none = DashboardCardActions();

  final ValueChanged<DashboardWidget>? onOpenDetail;

  VoidCallback? detailOf(DashboardWidget widget) {
    final open = onOpenDetail;
    if (open == null) return null;
    return () => open(widget);
  }
}

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

class DashboardBoard extends ConsumerWidget {
  const DashboardBoard({super.key, this.actions = DashboardCardActions.none});

  final DashboardCardActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final widgets = ref.watch(visibleDashboardWidgetsProvider);
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
          InlineNotice(
            message: context.l10n.dashboardEditHint,
            glyph: TablerIcons.info_circle,
            color: colorScheme.primaryContainer,
            foregroundColor: colorScheme.onPrimaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: widgets.length,
              onReorderItem: (oldIndex, newIndex) => ref
                  .read(dashboardWidgetsProvider.notifier)
                  .moveVisible(widgets, oldIndex, newIndex),
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
                        const Spacer(),
                        DashboardRemoveBadge(
                          onPressed: () => ref
                              .read(dashboardWidgetsProvider.notifier)
                              .remove(widget),
                        ),
                      ],
                    ),
                    child: buildDashboardCard(
                      widget,
                      DashboardCardActions.none,
                    ),
                  ),
                );
              },
            ),
          const _AddCardRow(),
        ],
      ),
    );
  }
}

class DashboardRemoveBadge extends StatelessWidget {
  const DashboardRemoveBadge({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Material(
      color: colorScheme.errorContainer,
      shape: AppShape.standard,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(
            TablerIcons.x,
            size: 16,
            color: colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

class DashboardDragBadge extends StatelessWidget {
  const DashboardDragBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      shape: AppShape.standard,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 28,
        height: 28,
        child: Icon(
          TablerIcons.grip_vertical,
          size: 16,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AddCardRow extends ConsumerWidget {
  const _AddCardRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    return OutlinedButton.icon(
      onPressed: () => showSheet<void>(
        context: context,
        builder: (_) => const DashboardEditSheet(),
      ),
      icon: Icon(TablerIcons.plus, size: 18, color: colorScheme.primary),
      label: Text(context.l10n.dashboardAddCard),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    );
  }
}
