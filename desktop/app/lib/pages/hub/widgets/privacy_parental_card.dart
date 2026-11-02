/// Parental control: block adult-content domains from a third-party category list.
///
/// The old desktop console's `ParentalControlCard.vue` is the blueprint. It shares the malicious-site
/// engine but not its switch, so it can be turned on alone; the warning is the only coupling the two
/// cards have, and it is the service's own condition (reputation lookups off) rather than a guess.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_reputation_providers.dart';
import 'package:diting_desktop/pages/hub/widgets/privacy_common.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class PrivacyParentalCard extends ConsumerWidget {
  const PrivacyParentalCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(desktopReputationProvider);
    final data = state.data;
    final saving = state.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopParentalTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.account,
            title: l10n.desktopParentalTitle,
            leading: [
              if (data != null)
                DashboardChip(
                  label: data.parentalEnabled
                      ? l10n.commonEnabled
                      : l10n.commonDisabled,
                  tone: data.parentalEnabled
                      ? DashboardChipTone.ok
                      : DashboardChipTone.idle,
                  dot: data.parentalEnabled,
                ),
            ],
            trailing: [
              if (saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else if (data != null)
                DashboardSwitch(
                  value: data.parentalEnabled,
                  semanticLabel: l10n.desktopParentalTitle,
                  onChanged: (value) => unawaited(
                    savePrivacySetting(
                      context,
                      ref,
                      () => ref
                          .read(desktopReputationProvider.notifier)
                          .save({'parentalEnabled': value}),
                      value
                          ? l10n.desktopParentalOn
                          : l10n.desktopParentalOff,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopParentalBody,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          if (data != null && !data.enabled) ...[
            const SizedBox(height: 8),
            Text(
              l10n.desktopParentalWarning,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(
                context,
                color: context.colorScheme.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
