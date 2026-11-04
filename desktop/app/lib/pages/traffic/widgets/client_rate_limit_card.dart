/// The token-bucket rate limit: one switch and the four numbers behind it.
///
/// The old desktop console's `ClientsPanel.vue` rate-limit card is the blueprint. The switch saves
/// the whole form (as the console did), and the numbers are a draft until the save button is used,
/// so a half-typed rate never reaches the service.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_traffic_models.dart';
import 'package:diting_desktop/data/api/desktop_traffic_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const double _fieldWidth = 150;

class ClientRateLimitCard extends ConsumerStatefulWidget {
  const ClientRateLimitCard({
    super.key,
    required this.rateLimit,
    required this.saving,
  });

  final DesktopRateLimit rateLimit;
  final bool saving;

  @override
  ConsumerState<ClientRateLimitCard> createState() =>
      _ClientRateLimitCardState();
}

class _ClientRateLimitCardState extends ConsumerState<ClientRateLimitCard> {
  final _rate = TextEditingController();
  final _burst = TextEditingController();
  final _ipv4 = TextEditingController();
  final _ipv6 = TextEditingController();
  final _exempt = TextEditingController();
  DesktopRateLimit? _adopted;
  bool _dirty = false;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _adopt(widget.rateLimit);
  }

  @override
  void didUpdateWidget(ClientRateLimitCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _adopt(widget.rateLimit);
  }

  @override
  void dispose() {
    _rate.dispose();
    _burst.dispose();
    _ipv4.dispose();
    _ipv6.dispose();
    _exempt.dispose();
    super.dispose();
  }

  void _adopt(DesktopRateLimit rateLimit) {
    if (identical(_adopted, rateLimit)) return;
    _adopted = rateLimit;
    if (_dirty) return;
    _apply(rateLimit);
  }

  void _apply(DesktopRateLimit rateLimit) {
    _rate.text = _trimZero(rateLimit.rate);
    _burst.text = '${rateLimit.burst}';
    _ipv4.text = '${rateLimit.ipv4Prefix}';
    _ipv6.text = '${rateLimit.ipv6Prefix}';
    _exempt.text = rateLimit.exemptIPs.join('\n');
  }

  static String _trimZero(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : '$value';

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  DesktopRateLimit _draft({bool? enabled}) {
    final exempt = [
      for (final line in _exempt.text.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    return DesktopRateLimit(
      enabled: enabled ?? widget.rateLimit.enabled,
      rate: double.tryParse(_rate.text) ?? 0,
      burst: int.tryParse(_burst.text) ?? 0,
      ipv4Prefix: int.tryParse(_ipv4.text) ?? 0,
      ipv6Prefix: int.tryParse(_ipv6.text) ?? 0,
      exemptIPs: exempt,
    );
  }

  bool _valid(DesktopRateLimit draft) =>
      draft.rate > 0 &&
      draft.burst > 0 &&
      draft.ipv4Prefix >= 1 &&
      draft.ipv4Prefix <= 32 &&
      draft.ipv6Prefix >= 1 &&
      draft.ipv6Prefix <= 128;

  Future<void> _save({bool? enabled, bool fromForm = false}) async {
    final l10n = context.l10n;
    final draft = _draft(enabled: enabled);
    if (!_valid(draft)) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    final error = await ref
        .read(desktopTrafficProvider.notifier)
        .saveRateLimit(draft);
    if (!mounted) return;
    if (error == null && fromForm) setState(() => _dirty = false);
    showDesktopMessage(
      context,
      error == null
          ? (draft.enabled
                ? l10n.desktopTrafficRateLimitSavedOn
                : l10n.desktopTrafficRateLimitSavedOff)
          : l10n.desktopTrafficSaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rateLimit = widget.rateLimit;
    final saving = widget.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopTrafficRateLimitTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.speed,
            title: l10n.desktopTrafficRateLimitTitle,
            leading: [
              DashboardChip(
                label: rateLimit.enabled
                    ? l10n.desktopTrafficRateLimitOn
                    : l10n.desktopTrafficRateLimitOff,
                tone: rateLimit.enabled
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
                dot: rateLimit.enabled,
              ),
            ],
            trailing: [
              if (saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else
                DashboardSwitch(
                  value: rateLimit.enabled,
                  semanticLabel: l10n.desktopTrafficRateLimitTitle,
                  onChanged: (value) =>
                      unawaited(_save(enabled: value)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopTrafficRateLimitBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Field(
                label: l10n.desktopTrafficRate,
                controller: _rate,
                onChanged: _markDirty,
                decimal: true,
              ),
              _Field(
                label: l10n.desktopTrafficBurst,
                controller: _burst,
                onChanged: _markDirty,
              ),
              _Field(
                label: l10n.desktopTrafficIpv4Prefix,
                controller: _ipv4,
                onChanged: _markDirty,
              ),
              _Field(
                label: l10n.desktopTrafficIpv6Prefix,
                controller: _ipv6,
                onChanged: _markDirty,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.desktopTrafficPrefixBody,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _exempt,
            minLines: 2,
            maxLines: 4,
            style: AppTextStyle.callout.of(context).toTabular,
            decoration: InputDecoration(
              labelText: l10n.desktopTrafficExempt,
              hintText: '127.0.0.1\n::1',
            ),
            onChanged: (_) => _markDirty(),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.desktopTrafficExemptBody,
            style: DashboardText.label(context),
          ),
          if (_invalid) ...[
            const SizedBox(height: 6),
            Text(
              l10n.desktopTrafficRateInvalid,
              style: DashboardText.label(
                context,
                color: context.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => setState(() {
                        _dirty = false;
                        _invalid = false;
                        _apply(rateLimit);
                      }),
                child: Text(l10n.desktopTrafficAccessReset),
              ),
              FilledButton.tonal(
                onPressed: saving
                    ? null
                    : () => unawaited(_save(fromForm: true)),
                child: Text(l10n.desktopTrafficRateLimitSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.decimal = false,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _fieldWidth,
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
          ),
        ],
        decoration: InputDecoration(labelText: label),
        style: AppTextStyle.callout.of(context).toTabular,
        onChanged: (_) => onChanged(),
      ),
    );
  }
}
