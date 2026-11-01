/// The configured upstream servers: each node's transport, address, weight, fingerprint state,
/// latency probe and the add/edit/delete actions. Mirrors `UpstreamPanel.vue`; it never edits the
/// running state, only the config the service re-reads after every save.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_upstream_models.dart';
import 'package:diting/desktop/data/api/desktop_upstream_providers.dart';
import 'package:diting/desktop/pages/hub/widgets/upstream_common.dart';
import 'package:diting/desktop/pages/hub/widgets/upstream_editor_dialog.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class UpstreamNodesCard extends ConsumerWidget {
  const UpstreamNodesCard({
    super.key,
    required this.config,
    required this.saving,
    required this.onChanged,
    required this.onSaveFailed,
  });

  final DesktopUpstreamConfig config;
  final bool saving;
  final ValueChanged<DesktopUpstreamConfig> onChanged;

  /// The page owns the save path; a failed probe reports here too.
  final void Function(String message) onSaveFailed;

  Future<void> _add(BuildContext context) async {
    final provider = await showUpstreamEditor(context);
    if (provider == null || !context.mounted) return;
    onChanged(
      config.copyWith(providers: [...config.providers, provider]),
    );
  }

  Future<void> _edit(BuildContext context, int index) async {
    final provider = await showUpstreamEditor(
      context,
      editing: config.providers[index],
    );
    if (provider == null || !context.mounted) return;
    final next = [...config.providers]..[index] = provider;
    onChanged(config.copyWith(providers: next));
  }

  Future<void> _delete(BuildContext context, int index) async {
    final l10n = context.l10n;
    if (config.providers.length <= 1) {
      await confirmDesktopAction(
        context,
        title: l10n.desktopUpstreamDeleteTitle,
        body: l10n.desktopUpstreamKeepOne,
        confirmLabel: l10n.commonConfirm,
        destructive: false,
        showCancel: false,
      );
      return;
    }
    final target = config.providers[index];
    final confirmed = await confirmDesktopAction(
      context,
      title: l10n.desktopUpstreamDeleteTitle,
      body: l10n.desktopUpstreamDeleteBody(target.id),
      confirmLabel: l10n.commonDelete,
    );
    if (!confirmed || !context.mounted) return;
    onChanged(
      config.copyWith(
        providers: [...config.providers]..removeAt(index),
      ),
    );
  }

  Future<void> _probe(
    BuildContext context,
    WidgetRef ref,
    DesktopUpstreamProvider provider,
  ) async {
    final result = await ref
        .read(desktopUpstreamProbeProvider.notifier)
        .test(provider);
    if (!context.mounted) return;
    if (result.error case final error?) {
      onSaveFailed(context.l10n.desktopUpstreamTestFailed(error));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final probes = ref.watch(desktopUpstreamProbeProvider);
    return DashboardCard(
      semanticLabel: l10n.desktopUpstreamNodesTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dns,
            title: l10n.desktopUpstreamNodesTitle,
            leading: [
              DashboardChip(
                label: l10n.desktopUpstreamNodesCount(config.providers.length),
              ),
            ],
            trailing: [
              DashboardIconButton(
                glyph: AppGlyphs.addCircle,
                tooltip: l10n.desktopUpstreamAdd,
                onPressed: saving ? null : () => _add(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopUpstreamNodesBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          if (config.providers.isEmpty)
            _EmptyNodes(onAdd: saving ? null : () => _add(context))
          else
            for (var index = 0; index < config.providers.length; index++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: index == config.providers.length - 1 ? 0 : 8,
                ),
                child: _NodeRow(
                  provider: config.providers[index],
                  probe: probes.results[config.providers[index].id],
                  probing: probes.isBusy(config.providers[index].id),
                  onTest: saving
                      ? null
                      : () => _probe(
                          context,
                          ref,
                          config.providers[index],
                        ),
                  onEdit: saving ? null : () => _edit(context, index),
                  onDelete: saving ? null : () => _delete(context, index),
                ),
              ),
        ],
      ),
    );
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.provider,
    required this.probe,
    required this.probing,
    required this.onTest,
    required this.onEdit,
    required this.onDelete,
  });

  final DesktopUpstreamProvider provider;
  final DesktopUpstreamProbe? probe;
  final bool probing;
  final VoidCallback? onTest;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return DashboardBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 4,
            children: [
              Expanded(
                child: Text(
                  provider.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context),
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
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DashboardChip(label: desktopProtocolLabel(provider.protocol)),
              if (provider.pin.isNotEmpty)
                DashboardChip(
                  label: l10n.desktopUpstreamPinSet,
                  tone: DashboardChipTone.ok,
                ),
              Text(
                l10n.desktopUpstreamWeight(provider.weight),
                style: DashboardText.label(context),
              ),
            ],
          ),
          Text(
            provider.address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.callout.of(context).toTabular,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (probe != null && probe!.success)
                DashboardChip(
                  label: '${probe!.latencyMs!.toStringAsFixed(1)} ms',
                  tone: DashboardChipTone.ok,
                )
              else if (probe != null && probe!.error != null)
                DashboardChip(
                  label: l10n.desktopUpstreamProbeFailed,
                  tone: DashboardChipTone.warn,
                ),
              TonalButton(
                size: TonalButtonSize.compact,
                glyph: AppGlyphs.bolt,
                label: l10n.desktopUpstreamTest,
                onPressed: probing ? null : onTest,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyNodes extends StatelessWidget {
  const _EmptyNodes({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text(
          l10n.desktopUpstreamEmpty,
          textAlign: TextAlign.center,
          style: DashboardText.rowTitle(context),
        ),
        Text(
          l10n.desktopUpstreamEmptyBody,
          textAlign: TextAlign.center,
          style: DashboardText.label(context),
        ),
        Center(
          child: TonalButton(
            size: TonalButtonSize.compact,
            glyph: AppGlyphs.addCircle,
            label: l10n.desktopUpstreamAdd,
            onPressed: onAdd,
          ),
        ),
      ],
    );
  }
}
