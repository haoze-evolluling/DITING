/// The local zones switch and their default TTL.
///
/// The old desktop console's `ZoneFileCard.vue` keeps these in the header of the zone list; here they
/// are their own card, because the list of editable RFC 1035 blocks needs the rest of the height. The
/// TTL is a draft that saves with its button; the switch saves on the spot.
library;

import 'dart:async';

import 'package:diting_desktop/widgets/desktop_spacing.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_zone_models.dart';
import 'package:diting_desktop/data/api/desktop_zone_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const double _numberWidth = 190;

class ZoneSettingsCard extends ConsumerStatefulWidget {
  const ZoneSettingsCard({super.key});

  @override
  ConsumerState<ZoneSettingsCard> createState() => _ZoneSettingsCardState();
}

class _ZoneSettingsCardState extends ConsumerState<ZoneSettingsCard> {
  final _ttl = TextEditingController();
  DesktopZoneConfig? _adopted;
  bool _ttlInvalid = false;

  @override
  void dispose() {
    _ttl.dispose();
    super.dispose();
  }

  void _adopt(DesktopZoneConfig config) {
    if (identical(_adopted, config)) return;
    _adopted = config;
    _ttl.text = '${config.effectiveTtl}';
  }

  Future<void> _toggle(bool enabled) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopZoneProvider.notifier)
        .setEnabled(enabled);
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (enabled ? l10n.desktopZoneToggleOn : l10n.desktopZoneToggleOff)
          : l10n.desktopZoneSaveFailed(error.message),
    );
  }

  Future<void> _saveTtl() async {
    final l10n = context.l10n;
    final ttl = int.tryParse(_ttl.text);
    if (ttl == null || ttl <= 0) {
      setState(() => _ttlInvalid = true);
      return;
    }
    setState(() => _ttlInvalid = false);
    final error = await ref.read(desktopZoneProvider.notifier).setTtl(ttl);
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopZoneTtlSaved
          : l10n.desktopZoneSaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(desktopZoneProvider);
    final config = state.config;
    if (config != null) _adopt(config);
    return DashboardCard(
      semanticLabel: l10n.desktopZoneSettingsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dns,
            title: l10n.desktopZoneSettingsTitle,
            leading: [
              if (config == null)
                const SizedBox.square(
                  dimension: 14,
                  child: CommonCircleLoading(),
                )
              else
                DashboardChip(
                  label: l10n.desktopZoneBadge(
                    config.zones.length,
                    config.maxZones,
                    config.recordCount,
                  ),
                ),
            ],
            trailing: [
              if (state.saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else if (config != null)
                DashboardSwitch(
                  value: config.enabled,
                  semanticLabel: l10n.desktopZoneSettingsTitle,
                  onChanged: (value) => unawaited(_toggle(value)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopZoneBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.desktopZoneRules,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: AppGap.sm,
            runSpacing: AppGap.field,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: _numberWidth,
                child: TextFormField(
                  controller: _ttl,
                  enabled: config != null && !state.saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l10n.desktopZoneDefaultTtl,
                  ),
                  style: AppTextStyle.callout.of(context),
                  onChanged: (_) {
                    if (_ttlInvalid) setState(() => _ttlInvalid = false);
                  },
                ),
              ),
              TonalButton(
                size: TonalButtonSize.compact,
                label: l10n.commonSave,
                onPressed: config == null || state.saving
                    ? null
                    : () => unawaited(_saveTtl()),
              ),
            ],
          ),
          if (_ttlInvalid) ...[
            const SizedBox(height: 8),
            Text(
              l10n.desktopZoneTtlInvalid,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: context.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
