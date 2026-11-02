/// The DNS64 synthesis prefixes: one RFC 6052 prefix per line, with the well-known one a button away.
///
/// The old desktop console's `DNS64Panel.vue` keeps this editor under the engine explanation; here it is
/// its own card. The list is a draft that saves with the button, and a prefix the service rejects is not
/// left on screen.
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

class Dns64PrefixesCard extends ConsumerStatefulWidget {
  const Dns64PrefixesCard({
    super.key,
    required this.config,
    required this.saving,
  });

  final DesktopDns64Config config;
  final bool saving;

  @override
  ConsumerState<Dns64PrefixesCard> createState() => _Dns64PrefixesCardState();
}

class _Dns64PrefixesCardState extends ConsumerState<Dns64PrefixesCard> {
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
  void didUpdateWidget(Dns64PrefixesCard oldWidget) {
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

  Future<void> _save() async {
    final l10n = context.l10n;
    final error = await ref.read(desktopDns64Provider.notifier).save(
      widget.config.copyWith(
        prefixes: desktopDns64ParsePrefixes(_prefixes.text),
      ),
    );
    if (!mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? l10n.desktopDns64Saved
          : l10n.desktopDns64SaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final saving = widget.saving;
    return DashboardCard(
      semanticLabel: l10n.desktopDns64PrefixesCardTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.layers,
            title: l10n.desktopDns64PrefixesCardTitle,
            trailing: [
              if (saving)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopDns64PrefixesHelper,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
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
                onPressed: saving
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
            decoration: const InputDecoration(
              hintText: desktopDns64WellKnownPrefix,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonalIcon(
              onPressed: saving ? null : () => unawaited(_save()),
              icon: saving
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CommonCircleLoading(),
                    )
                  : const GlyphIcon(AppGlyphs.check, size: 16),
              label: Text(
                saving ? l10n.desktopDns64Saving : l10n.desktopDns64Save,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
