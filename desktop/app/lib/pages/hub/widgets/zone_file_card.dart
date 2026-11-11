/// The local authoritative zones: one row per zone with its build result, an expandable RFC 1035 text
/// area, and a preview that runs the service's own parser before saving.
///
/// The old desktop console's `ZoneFileCard.vue` is the blueprint. Zone text is edited locally and only
/// "save all" posts it; a rejected save rolls the list back to what the service still holds. The switch
/// and the default TTL are [ZoneSettingsCard], because a list of editable blocks and its header
/// settings in one card made it the tallest card in the window.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_client.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_zone_models.dart';
import 'package:diting_desktop/data/api/desktop_zone_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Below this the state chip moves under the row, so a narrow window does not squeeze the apex.
const double _chipInlineBreakpoint = 560;

const double _badgeWidth = 132;

/// A new zone starts as a working example, exactly like the console's template.
const String _zoneTemplate =
    '\$ORIGIN example.lan.\n'
    '@   IN SOA ns.example.lan. admin.example.lan. (1 7200 3600 1209600 300)\n'
    'www IN A 192.168.1.10\n';

class ZoneFileCard extends ConsumerStatefulWidget {
  const ZoneFileCard({super.key});

  @override
  ConsumerState<ZoneFileCard> createState() => _ZoneFileCardState();
}

class _ZoneFileCardState extends ConsumerState<ZoneFileCard> {
  final _zones = <DesktopZoneEntry>[];
  final _previews = <String, ({bool ok, String text})>{};

  /// The provider's zone list this card last copied, by identity. A new answer replaces the drafts;
  /// a rebuild for any other reason leaves them alone.
  List<DesktopZoneEntry>? _adopted;

  String _expanded = '';

  void _adopt(DesktopZoneConfig config) {
    if (identical(_adopted, config.zones)) return;
    _adopted = config.zones;
    _zones
      ..clear()
      ..addAll(config.zones);
    _previews.clear();
  }

  /// Posts the whole list. On a rejection the drafts go back to [rollback], because a zone list the
  /// service did not accept must not stay on screen as if it had been applied.
  Future<void> _persist({
    required List<DesktopZoneEntry> rollback,
    String? success,
  }) async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopZoneProvider.notifier)
        .saveZones(List.of(_zones));
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _zones
          ..clear()
          ..addAll(rollback);
        _previews.clear();
      });
    }
    showDesktopMessage(
      context,
      error == null
          ? (success ?? l10n.desktopZoneSaved)
          : l10n.desktopZoneSaveFailed(error.message),
    );
  }

  void _add(DesktopZoneConfig config) {
    final l10n = context.l10n;
    if (_zones.length >= config.maxZones) {
      showDesktopMessage(context, l10n.desktopZoneMaxZones(config.maxZones));
      return;
    }
    final zone = DesktopZoneEntry(
      id: 'zone-${DateTime.now().microsecondsSinceEpoch}',
      origin: '',
      content: _zoneTemplate,
      enabled: true,
    );
    setState(() {
      _zones.add(zone);
      _expanded = zone.id;
    });
  }

  Future<void> _delete(DesktopZoneEntry zone) async {
    final l10n = context.l10n;
    final rollback = List.of(_zones);
    setState(() {
      _zones.removeWhere((item) => item.id == zone.id);
      if (_expanded == zone.id) _expanded = '';
      _previews.remove(zone.id);
    });
    await _persist(
      rollback: rollback,
      success: l10n.desktopZoneDeleted(
        zone.origin.isEmpty ? l10n.desktopZoneUnnamed : zone.origin,
      ),
    );
  }

  void _touch(String id, {String? origin, String? content, bool? enabled}) {
    final index = _zones.indexWhere((zone) => zone.id == id);
    if (index < 0) return;
    _zones[index] = _zones[index].copyWith(
      origin: origin,
      content: content,
      enabled: enabled,
    );
    _previews.remove(id);
  }

  Future<void> _preview(DesktopZoneEntry zone, int ttl) async {
    final l10n = context.l10n;
    try {
      final result = await ref
          .read(desktopApiClientProvider)
          .testZone(origin: zone.origin, content: zone.content, ttl: ttl);
      if (!mounted) return;
      setState(() {
        if (result.success) {
          final lines = result.records.take(20).toList();
          final text = [
            ...lines,
            if (result.records.length > lines.length)
              l10n.desktopZonePreviewMore(result.records.length - lines.length),
          ].join('\n');
          _previews[zone.id] = (
            ok: true,
            text: text.isEmpty ? l10n.desktopZonePreviewEmpty : text,
          );
        } else {
          _previews[zone.id] = (
            ok: false,
            text: result.error.isEmpty
                ? l10n.desktopZoneFailedReason
                : result.error,
          );
        }
      });
    } on DesktopApiException catch (error) {
      if (!mounted) return;
      setState(() => _previews[zone.id] = (ok: false, text: error.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(desktopZoneProvider);
    final config = state.config;
    if (config != null) _adopt(config);
    return DashboardCard(
      semanticLabel: l10n.desktopZoneTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.rules,
            title: l10n.desktopZoneTitle,
            leading: [
              DashboardChip(
                label: l10n.desktopZoneBadge(
                  _zones.length,
                  config?.maxZones ?? _zones.length,
                  config?.recordCount ?? 0,
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
                DashboardChip(
                  label: config.enabled
                      ? l10n.commonEnabled
                      : l10n.commonDisabled,
                  tone: config.enabled
                      ? DashboardChipTone.ok
                      : DashboardChipTone.idle,
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (config == null)
            _Unavailable(
              error: state.error,
              onRetry: ref.read(desktopZoneProvider.notifier).reload,
            )
          else ...[
            Text(
              l10n.desktopZoneLimit(config.maxRecords),
              style: DashboardText.label(context),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TonalButton(
                  size: TonalButtonSize.compact,
                  glyph: AppGlyphs.add,
                  label: l10n.desktopZoneAdd,
                  onPressed: state.saving ? null : () => _add(config),
                ),
                TonalButton(
                  size: TonalButtonSize.compact,
                  glyph: AppGlyphs.check,
                  label: l10n.desktopZoneSaveAll,
                  onPressed: state.saving || _zones.isEmpty
                      ? null
                      : () => unawaited(
                          _persist(rollback: List.of(_zones)),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_zones.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  l10n.desktopZoneEmpty,
                  textAlign: TextAlign.center,
                  style: DashboardText.label(context),
                ),
              )
            else
              for (final zone in _zones) ...[
                _zoneRow(
                  context,
                  zone,
                  config,
                  state.saving,
                  config.effectiveTtl,
                ),
                const SizedBox(height: 8),
              ],
          ],
        ],
      ),
    );
  }

  Widget _zoneRow(
    BuildContext context,
    DesktopZoneEntry zone,
    DesktopZoneConfig config,
    bool saving,
    int ttl,
  ) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final expanded = _expanded == zone.id;
    final badge = _stateBadge(context, zone, config);
    final state = config.stateOf(zone.id);
    final failure =
        zone.enabled &&
        state != null &&
        (!state.loaded || state.error.isNotEmpty);
    final preview = _previews[zone.id];
    final mono = AppTextStyle.callout
        .of(context)
        .copyWith(fontFeatures: appTabularFigures);
    final chip = SizedBox(
      width: _badgeWidth,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: DashboardChip(label: badge.label, tone: badge.tone),
      ),
    );
    return DashboardBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final inline = constraints.maxWidth >= _chipInlineBreakpoint;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 6,
                children: [
                  Row(
                    spacing: 8,
                    children: [
                      SizedBox.square(
                        dimension: 32,
                        child: DashboardIconButton(
                          glyph: expanded
                              ? AppGlyphs.chevronDown
                              : AppGlyphs.chevronForward,
                          tooltip: expanded
                              ? l10n.desktopZoneCollapse
                              : l10n.desktopZoneExpand,
                          onPressed: () => setState(
                            () => _expanded = expanded ? '' : zone.id,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('${zone.id}-origin'),
                          initialValue: zone.origin,
                          decoration: InputDecoration(
                            hintText: l10n.desktopZoneOriginHint,
                          ),
                          style: mono,
                          onChanged: (value) => _touch(zone.id, origin: value),
                        ),
                      ),
                      if (inline) chip,
                      DashboardSwitch(
                        value: zone.enabled,
                        semanticLabel: zone.id,
                        onChanged: saving
                            ? null
                            : (value) => setState(
                                () => _touch(zone.id, enabled: value),
                              ),
                      ),
                      SizedBox.square(
                        dimension: 32,
                        child: DashboardIconButton(
                          glyph: AppGlyphs.delete,
                          tooltip: l10n.desktopZoneDelete,
                          onPressed: saving
                              ? null
                              : () => unawaited(_delete(zone)),
                        ),
                      ),
                    ],
                  ),
                  if (!inline)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: chip,
                    ),
                ],
              );
            },
          ),
          if (failure)
            Text(
              state.error.isEmpty ? l10n.desktopZoneFailedReason : state.error,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: colorScheme.error),
            ),
          if (expanded) ...[
            TextFormField(
              key: ValueKey('${zone.id}-content'),
              initialValue: zone.content,
              minLines: 8,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(labelText: l10n.desktopZoneContent),
              style: mono,
              onChanged: (value) => _touch(zone.id, content: value),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TonalButton(
                  size: TonalButtonSize.compact,
                  glyph: AppGlyphs.check,
                  label: l10n.desktopZonePreview,
                  onPressed: () => unawaited(_preview(zone, ttl)),
                ),
                Text(
                  l10n.desktopZonePreviewNote,
                  style: DashboardText.label(context),
                ),
              ],
            ),
            if (preview != null)
              DashboardBlock(
                child: Text(
                  preview.text,
                  maxLines: 20,
                  overflow: TextOverflow.ellipsis,
                  style: mono.copyWith(
                    color: preview.ok
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.error,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  ({String label, DashboardChipTone tone}) _stateBadge(
    BuildContext context,
    DesktopZoneEntry zone,
    DesktopZoneConfig config,
  ) {
    final l10n = context.l10n;
    if (!zone.enabled) {
      return (
        label: l10n.desktopZoneStateDisabled,
        tone: DashboardChipTone.idle,
      );
    }
    final state = config.stateOf(zone.id);
    if (state == null) {
      return (
        label: l10n.desktopZoneStatePending,
        tone: DashboardChipTone.idle,
      );
    }
    if (!state.loaded) {
      return (label: l10n.desktopZoneStateFailed, tone: DashboardChipTone.warn);
    }
    if (state.error.isNotEmpty) {
      return (
        label: l10n.desktopZoneStateTruncated(state.records),
        tone: DashboardChipTone.warn,
      );
    }
    return (
      label: l10n.desktopZoneStateLoaded(state.records),
      tone: DashboardChipTone.ok,
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.error, required this.onRetry});

  final DesktopApiException? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        spacing: 8,
        children: [
          GlyphIcon(
            AppGlyphs.warning,
            size: 18,
            color: context.colorScheme.warning,
          ),
          Expanded(
            child: Text(
              error == null
                  ? l10n.desktopZoneLoadFailed
                  : '${l10n.desktopZoneLoadFailed} · ${error!.message}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.rowTitle(context),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(l10n.desktopRetry)),
        ],
      ),
    );
  }
}
