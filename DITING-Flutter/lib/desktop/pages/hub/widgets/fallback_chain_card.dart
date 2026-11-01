/// The independent fallback chain: a second chain the resolver only enters when the whole main
/// chain fails or returns one of the selected response codes. `FallbackUpstreamCard.vue` defines the
/// behaviour, including that clearing the chain is how the chain is turned off.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_upstream_models.dart';
import 'package:diting/desktop/pages/hub/widgets/upstream_common.dart';
import 'package:diting/desktop/pages/hub/widgets/upstream_editor_dialog.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Response codes offered as fallback triggers. NOERROR and NXDOMAIN are meaningful answers, so the
/// console leaves NXDOMAIN off by default.
const _rcodeChoices = [
  (value: 2, label: 'SERVFAIL'),
  (value: 5, label: 'REFUSED'),
  (value: 4, label: 'NOTIMP'),
  (value: 3, label: 'NXDOMAIN'),
];

class FallbackChainCard extends StatelessWidget {
  const FallbackChainCard({
    super.key,
    required this.config,
    required this.saving,
    required this.onChanged,
  });

  final DesktopUpstreamConfig config;
  final bool saving;
  final ValueChanged<DesktopUpstreamConfig> onChanged;

  void _toggle() {
    if (config.fallbackEnabled) {
      onChanged(config.copyWith(fallbackProviders: const []));
      return;
    }
    onChanged(
      config.copyWith(
        fallbackProviders: const [
          DesktopUpstreamProvider(
            id: 'fallback-1',
            protocol: 'DOT',
            server: 'dns.alidns.com:853',
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final provider = await showUpstreamEditor(context);
    if (provider == null || !context.mounted) return;
    onChanged(
      config.copyWith(
        fallbackProviders: [...config.fallbackProviders, provider],
      ),
    );
  }

  Future<void> _edit(BuildContext context, int index) async {
    final provider = await showUpstreamEditor(
      context,
      editing: config.fallbackProviders[index],
    );
    if (provider == null || !context.mounted) return;
    final next = [...config.fallbackProviders]..[index] = provider;
    onChanged(config.copyWith(fallbackProviders: next));
  }

  void _delete(int index) {
    onChanged(
      config.copyWith(
        fallbackProviders: [...config.fallbackProviders]..removeAt(index),
      ),
    );
  }

  void _toggleRcode(int code) {
    final next = {...config.fallbackOnRcode};
    if (!next.remove(code)) next.add(code);
    final sorted = next.toList()..sort();
    onChanged(config.copyWith(fallbackOnRcode: sorted));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DashboardCard(
      semanticLabel: l10n.desktopUpstreamFallbackTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.lock,
            title: l10n.desktopUpstreamFallbackTitle,
            leading: [
              DashboardChip(
                label: config.fallbackEnabled
                    ? l10n.desktopUpstreamFallbackCount(
                        config.fallbackProviders.length,
                      )
                    : l10n.desktopUpstreamFallbackOff,
                tone: config.fallbackEnabled
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
              ),
            ],
            trailing: [
              DashboardSwitch(
                value: config.fallbackEnabled,
                semanticLabel: l10n.desktopUpstreamFallbackTitle,
                onChanged: saving ? null : (_) => _toggle(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopUpstreamFallbackNote,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          if (!config.fallbackEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n.desktopUpstreamFallbackEmpty,
                textAlign: TextAlign.center,
                style: DashboardText.label(context),
              ),
            )
          else ...[
            for (var index = 0; index < config.fallbackProviders.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _FallbackRow(
                  provider: config.fallbackProviders[index],
                  onEdit: saving ? null : () => _edit(context, index),
                  onDelete: saving ? null : () => _delete(index),
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TonalButton(
                size: TonalButtonSize.compact,
                glyph: AppGlyphs.addCircle,
                label: l10n.desktopUpstreamFallbackAdd,
                onPressed: saving ? null : () => _add(context),
              ),
            ),
            const SizedBox(height: 14),
            _TimeoutField(
              value: config.effectiveFallbackTimeoutMs,
              enabled: !saving,
              onChanged: (value) => onChanged(
                config.copyWith(fallbackTimeoutMs: value),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.desktopUpstreamFallbackRcode,
              style: DashboardText.rowTitle(context),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final choice in _rcodeChoices)
                  _RcodeChip(
                    label: choice.label,
                    selected: config.fallbackOnRcode.contains(choice.value),
                    onPressed: saving
                        ? null
                        : () => _toggleRcode(choice.value),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.desktopUpstreamFallbackRcodeHint,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.label(context),
            ),
            const SizedBox(height: 10),
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: Text(
                    l10n.desktopUpstreamFallbackOnError,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DashboardText.label(context),
                  ),
                ),
                DashboardSwitch(
                  value: config.fallbackOnError,
                  semanticLabel: l10n.desktopUpstreamFallbackOnError,
                  onChanged: saving
                      ? null
                      : (value) => onChanged(
                          config.copyWith(fallbackOnError: value),
                        ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FallbackRow extends StatelessWidget {
  const _FallbackRow({
    required this.provider,
    required this.onEdit,
    required this.onDelete,
  });

  final DesktopUpstreamProvider provider;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          DashboardChip(label: desktopProtocolLabel(provider.protocol)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  provider.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context),
                ),
                Text(
                  provider.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context)
                      .toTabular
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.commonEdit,
            onPressed: onEdit,
            icon: const GlyphIcon(AppGlyphs.settings, size: 18),
          ),
          IconButton(
            tooltip: l10n.commonDelete,
            onPressed: onDelete,
            icon: GlyphIcon(
              AppGlyphs.delete,
              size: 18,
              color: colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _RcodeChip extends StatelessWidget {
  const _RcodeChip({
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
    final foreground = selected ? colorScheme.onPrimary : null;
    return CommonCard(
      isSelected: selected,
      fillsSelection: true,
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        label,
        style: AppTextStyle.caption1
            .of(context, emphasized: true)
            .toTabular
            .copyWith(color: foreground),
      ),
    );
  }
}

class _TimeoutField extends StatefulWidget {
  const _TimeoutField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<_TimeoutField> createState() => _TimeoutFieldState();
}

class _TimeoutFieldState extends State<_TimeoutField> {
  late final _controller = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(covariant _TimeoutField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow the service when it reports a different value, but never while the user is typing a
    // value the service has not seen yet.
    if (oldWidget.value != widget.value &&
        _controller.text == '${oldWidget.value}') {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    final raw = int.tryParse(_controller.text.trim());
    final clamped = raw == null || raw <= 0
        ? DesktopUpstreamConfig.defaultFallbackTimeoutMs
        : raw.clamp(100, 30000);
    _controller.text = '$clamped';
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 8,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: _controller,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: context.l10n.desktopUpstreamFallbackTimeout,
            ),
            style: AppTextStyle.callout.of(context),
            onFieldSubmitted: (_) => _apply(),
          ),
        ),
        IconButton(
          tooltip: context.l10n.commonSave,
          onPressed: widget.enabled ? _apply : null,
          icon: const GlyphIcon(AppGlyphs.check, size: 18),
        ),
      ],
    );
  }
}
