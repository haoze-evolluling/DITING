/// The DNS64 synthesizer card: the engine switch, the RFC 6052 prefix list and the protections the
/// service applies on its own.
///
/// The old desktop console's `DNS64Panel.vue` is the blueprint. The switch saves the moment it
/// moves and carries the prefixes as typed, the save button posts the whole form, and both re-read
/// `/status`, so a prefix the service rejected never stays on screen as if it had been applied.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_dns64_models.dart';
import 'package:diting_desktop/data/api/desktop_dns64_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class Dns64Card extends ConsumerStatefulWidget {
  const Dns64Card({super.key, required this.config, required this.saving});

  final DesktopDns64Config config;
  final bool saving;

  @override
  ConsumerState<Dns64Card> createState() => _Dns64CardState();
}

class _Dns64CardState extends ConsumerState<Dns64Card> {
  /// The prefixes as typed. Adopted from the service only when a new answer arrives, so a rebuild
  /// never overwrites what is being edited.
  final _prefixes = TextEditingController();
  DesktopDns64Config? _adopted;

  @override
  void initState() {
    super.initState();
    _adopt(widget.config);
  }

  @override
  void didUpdateWidget(Dns64Card oldWidget) {
    super.didUpdateWidget(oldWidget);
    _adopt(widget.config);
  }

  @override
  void dispose() {
    _prefixes.dispose();
    super.dispose();
  }

  void _adopt(DesktopDns64Config config) {
    if (identical(_adopted, config)) return;
    _adopted = config;
    _prefixes.text = config.prefixText;
  }

  Future<void> _save(DesktopDns64Config next, {required bool toggle}) async {
    final l10n = context.l10n;
    final error = await ref.read(desktopDns64Provider.notifier).save(next);
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (toggle
                ? (next.enabled
                      ? l10n.desktopDns64ToggleOn
                      : l10n.desktopDns64ToggleOff)
                : l10n.desktopDns64Saved)
          : l10n.desktopDns64SaveFailed(error.message),
    );
  }

  /// The switch sends the typed prefixes too, exactly like the console: moving the switch must not
  /// silently drop an edit that is already on screen.
  void _toggle(bool enabled) {
    unawaited(
      _save(
        widget.config.copyWith(
          enabled: enabled,
          prefixes: desktopDns64ParsePrefixes(_prefixes.text),
        ),
        toggle: true,
      ),
    );
  }

  void _submit() {
    unawaited(
      _save(
        widget.config.copyWith(
          prefixes: desktopDns64ParsePrefixes(_prefixes.text),
        ),
        toggle: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final config = widget.config;
    final colorScheme = context.colorScheme;
    return DashboardCard(
      semanticLabel: l10n.desktopDns64CardTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dns,
            title: l10n.desktopDns64CardTitle,
            leading: [
              DashboardChip(
                label: config.enabled
                    ? l10n.desktopDns64EngineOn
                    : l10n.desktopDns64EngineOff,
                tone: config.enabled
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
                dot: true,
              ),
            ],
            trailing: [
              DashboardSwitch(
                value: config.enabled,
                semanticLabel: l10n.desktopDns64CardTitle,
                onChanged: widget.saving ? null : _toggle,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.desktopDns64CardBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.desktopDns64Description,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.desktopDns64PrefixesLabel,
                style: DashboardText.rowTitle(context),
              ),
              TextButton(
                onPressed: widget.saving
                    ? null
                    : () => setState(
                        () => _prefixes.text = desktopDns64WellKnownPrefix,
                      ),
                child: Text(l10n.desktopDns64FillWellKnown),
              ),
            ],
          ),
          TextField(
            controller: _prefixes,
            minLines: 3,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            style: AppTextStyle.callout.of(context).toMonospace,
            decoration: const InputDecoration(hintText: desktopDns64WellKnownPrefix),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopDns64PrefixesHelper,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 14),
          DashboardBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 4,
              children: [
                Row(
                  spacing: 6,
                  children: [
                    GlyphIcon(
                      AppGlyphs.info,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                    Expanded(
                      child: Text(
                        l10n.desktopDns64NoteTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashboardText.rowTitle(context),
                      ),
                    ),
                  ],
                ),
                Text(
                  l10n.desktopDns64NoteBody,
                  style: DashboardText.label(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonalIcon(
              onPressed: widget.saving ? null : _submit,
              icon: widget.saving
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CommonCircleLoading(),
                    )
                  : const GlyphIcon(AppGlyphs.check, size: 16),
              label: Text(
                widget.saving
                    ? l10n.desktopDns64Saving
                    : l10n.desktopDns64Save,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
