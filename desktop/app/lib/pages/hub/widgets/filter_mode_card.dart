/// The blocking response: the three answer modes, and the save button that posts the choice.
///
/// The old desktop console's `RulesPanel.vue` "config" tab is the blueprint. The mode tiles are a local
/// draft; only the button posts, and the card then adopts what the service kept. The response
/// addresses and the list refresh interval are [FilterBlockingParamsCard], so a mode picker and three
/// fields do not share one card.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_filter_config_models.dart';
import 'package:diting_desktop/data/api/desktop_filter_config_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_desktop/widgets/desktop_option_tile.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const double _fieldWidth = 190;

class FilterModeCard extends ConsumerStatefulWidget {
  const FilterModeCard({super.key, required this.config, required this.saving});

  final DesktopFilterConfig config;
  final bool saving;

  @override
  ConsumerState<FilterModeCard> createState() => _FilterModeCardState();
}

class _FilterModeCardState extends ConsumerState<FilterModeCard> {
  DesktopFilterConfig? _adopted;
  String _mode = desktopBlockModes.first;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _adopt(widget.config);
  }

  @override
  void didUpdateWidget(FilterModeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _adopt(widget.config);
  }

  /// Adopts the service's mode only when a new answer arrives and nothing has been picked since.
  void _adopt(DesktopFilterConfig config) {
    if (identical(_adopted, config)) return;
    _adopted = config;
    if (_dirty) return;
    _mode = config.effectiveBlockMode;
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final error = await ref
        .read(desktopFilterConfigProvider.notifier)
        .save(widget.config.copyWith(blockMode: _mode));
    if (!mounted) return;
    if (error == null) setState(() => _dirty = false);
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopFilterModeSaved
          : l10n.desktopFilterConfigSaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DashboardCard(
      semanticLabel: l10n.desktopFilterModeTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.rules,
            title: l10n.desktopFilterModeTitle,
            trailing: [
              if (widget.saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else
                DashboardIconButton(
                  glyph: AppGlyphs.check,
                  tooltip: l10n.desktopFilterModeSave,
                  onPressed: _save,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopFilterModeBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          for (final mode in desktopBlockModes) ...[
            DesktopOptionTile(
              label: desktopBlockModeLabel(context, mode),
              description: desktopBlockModeBody(context, mode),
              selected: _mode == mode,
              onPressed: widget.saving
                  ? null
                  : () {
                      setState(() {
                        _mode = mode;
                        _dirty = true;
                      });
                    },
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonalIcon(
              onPressed: widget.saving ? null : () => unawaited(_save()),
              icon: const GlyphIcon(AppGlyphs.check, size: 16),
              label: Text(
                widget.saving
                    ? l10n.desktopFilterModeSaving
                    : l10n.desktopFilterModeSave,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The addresses a blocked name is answered with, and the interval the rule lists refresh on.
class FilterBlockingParamsCard extends ConsumerStatefulWidget {
  const FilterBlockingParamsCard({
    super.key,
    required this.config,
    required this.saving,
  });

  final DesktopFilterConfig config;
  final bool saving;

  @override
  ConsumerState<FilterBlockingParamsCard> createState() =>
      _FilterBlockingParamsCardState();
}

class _FilterBlockingParamsCardState
    extends ConsumerState<FilterBlockingParamsCard> {
  final _ipv4 = TextEditingController();
  final _ipv6 = TextEditingController();
  final _interval = TextEditingController();
  DesktopFilterConfig? _adopted;
  bool _dirty = false;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _adopt(widget.config);
  }

  @override
  void didUpdateWidget(FilterBlockingParamsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _adopt(widget.config);
  }

  @override
  void dispose() {
    _ipv4.dispose();
    _ipv6.dispose();
    _interval.dispose();
    super.dispose();
  }

  /// Adopts the service's values only when a new answer arrives and nothing is being edited; a
  /// switch elsewhere must not silently discard a half-typed address.
  void _adopt(DesktopFilterConfig config) {
    if (identical(_adopted, config)) return;
    _adopted = config;
    if (_dirty) return;
    _ipv4.text = config.blockingIPv4;
    _ipv6.text = config.blockingIPv6;
    _interval.text = '${config.effectiveIntervalHours}';
  }

  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final interval = int.tryParse(_interval.text);
    final valid =
        interval != null &&
        interval > 0 &&
        _ipv4.text.trim().isNotEmpty &&
        _ipv6.text.trim().isNotEmpty;
    if (!valid) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    final error = await ref
        .read(desktopFilterConfigProvider.notifier)
        .save(
          widget.config.copyWith(
            blockingIPv4: _ipv4.text.trim(),
            blockingIPv6: _ipv6.text.trim(),
            updateIntervalHours: interval,
          ),
        );
    if (!mounted) return;
    if (error == null) setState(() => _dirty = false);
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopFilterModeSaved
          : l10n.desktopFilterConfigSaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return DashboardCard(
      semanticLabel: l10n.desktopFilterModeParamsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.sliders,
            title: l10n.desktopFilterModeParamsTitle,
            trailing: [
              if (widget.saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopFilterModeParamsBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _AddressField(
                label: l10n.desktopFilterModeBlockingIPv4,
                controller: _ipv4,
                onChanged: _markDirty,
              ),
              _AddressField(
                label: l10n.desktopFilterModeBlockingIPv6,
                controller: _ipv6,
                onChanged: _markDirty,
              ),
              SizedBox(
                width: _fieldWidth,
                child: TextFormField(
                  controller: _interval,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l10n.desktopFilterModeInterval,
                    helperText: l10n.desktopFilterModeIntervalHelper,
                  ),
                  style: AppTextStyle.callout.of(context),
                  onChanged: (_) => _markDirty(),
                ),
              ),
            ],
          ),
          if (_invalid) ...[
            const SizedBox(height: 8),
            Text(
              l10n.desktopFilterModeInvalid,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(context, color: colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonalIcon(
              onPressed: widget.saving ? null : () => unawaited(_save()),
              icon: const GlyphIcon(AppGlyphs.check, size: 16),
              label: Text(
                widget.saving
                    ? l10n.desktopFilterModeSaving
                    : l10n.desktopFilterModeSave,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressField extends StatelessWidget {
  const _AddressField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _fieldWidth,
      child: TextFormField(
        controller: controller,
        style: AppTextStyle.callout.of(context).toTabular,
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

/// The console's three mode labels and their explanations.
String desktopBlockModeLabel(BuildContext context, String mode) {
  final l10n = context.l10n;
  return switch (mode) {
    'nxdomain' => l10n.desktopFilterModeNxdomain,
    'refused' => l10n.desktopFilterModeRefused,
    _ => l10n.desktopFilterModeNullIp,
  };
}

String desktopBlockModeBody(BuildContext context, String mode) {
  final l10n = context.l10n;
  return switch (mode) {
    'nxdomain' => l10n.desktopFilterModeNxdomainBody,
    'refused' => l10n.desktopFilterModeRefusedBody,
    _ => l10n.desktopFilterModeNullIpBody,
  };
}
