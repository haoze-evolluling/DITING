/// The built-in service groups: one tap blocks or unblocks every service in the group.
///
/// The old desktop console's `ServicesPanel.vue` group row is the blueprint. It sits above the service
/// list as its own card, because the chips, the active-rule count and the clear-all button are a
/// different question from the searchable list of services.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_services_models.dart';
import 'package:diting_desktop/data/api/desktop_services_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class BlockedServiceGroupsCard extends ConsumerStatefulWidget {
  const BlockedServiceGroupsCard({super.key});

  @override
  ConsumerState<BlockedServiceGroupsCard> createState() =>
      _BlockedServiceGroupsCardState();
}

class _BlockedServiceGroupsCardState
    extends ConsumerState<BlockedServiceGroupsCard> {
  Future<void> _toggleGroup(DesktopServiceGroup group) async {
    final l10n = context.l10n;
    final blocked = ref
        .read(desktopServicesProvider)
        .data
        ?.blockedGroups
        .contains(group.id);
    final error = await ref
        .read(desktopServicesProvider.notifier)
        .toggleGroup(group);
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (blocked == true
                ? l10n.desktopServicesGroupOff(group.name)
                : l10n.desktopServicesGroupOn(group.name))
          : l10n.desktopServicesActionFailed(error.message),
    );
  }

  Future<void> _clearAll() async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopServicesProvider.notifier)
        .clearAll();
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopServicesCleared
          : l10n.desktopServicesActionFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(desktopServicesProvider);
    final data = state.data;
    final saving = state.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopServicesGroupsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.appsList,
            title: l10n.desktopServicesGroupsTitle,
            leading: [
              if (data != null)
                DashboardChip(
                  label: l10n.desktopServicesActiveRules(data.activeRules),
                ),
            ],
            trailing: [
              if (saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else
                DashboardIconButton(
                  glyph: AppGlyphs.clearAll,
                  tooltip: l10n.desktopServicesClearAll,
                  onPressed: data == null || data.blockedCount == 0
                      ? null
                      : () => unawaited(_clearAll()),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopServicesGroupsBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          if (data == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CommonCircleLoading(size: 20)),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final group in data.groups)
                  _GroupChip(
                    label: l10n.desktopServicesGroupChip(
                      group.name,
                      group.count,
                    ),
                    selected: data.blockedGroups.contains(group.id),
                    onPressed: saving
                        ? null
                        : () => unawaited(_toggleGroup(group)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonCard(
      isSelected: selected,
      fillsSelection: true,
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        label,
        style: AppTextStyle.caption1
            .of(context, emphasized: true)
            .copyWith(color: selected ? colorScheme.onPrimary : null),
      ),
    );
  }
}

