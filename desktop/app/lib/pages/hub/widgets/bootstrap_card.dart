/// Bootstrap DNS: the servers used to resolve an encrypted upstream's host name before the TLS
/// handshake. The console's `BootstrapConfigCard.vue` is the blueprint: the switch applies at once,
/// at least one server is kept, and each server can be probed.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_upstream_models.dart';
import 'package:diting_desktop/data/api/desktop_upstream_providers.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const _bootstrapPresets = [
  (name: 'AliDNS', address: '223.5.5.5:53'),
  (name: 'DNSPod', address: '119.29.29.29:53'),
  (name: 'Google', address: '8.8.8.8:53'),
  (name: 'Cloudflare', address: '1.1.1.1:53'),
];

class BootstrapCard extends ConsumerWidget {
  const BootstrapCard({
    super.key,
    required this.config,
    required this.saving,
    required this.onChanged,
    required this.onSaveFailed,
  });

  final DesktopUpstreamConfig config;
  final bool saving;
  final ValueChanged<DesktopUpstreamConfig> onChanged;
  final void Function(String message) onSaveFailed;

  Future<void> _add(BuildContext context) async {
    final server = await showBootstrapEditor(
      context,
      nextIndex: config.bootstrapServers.length + 1,
    );
    if (server == null || !context.mounted) return;
    onChanged(
      config.copyWith(
        bootstrapServers: [...config.bootstrapServers, server],
      ),
    );
  }

  Future<void> _edit(BuildContext context, int index) async {
    final server = await showBootstrapEditor(
      context,
      editing: config.bootstrapServers[index],
      nextIndex: index + 1,
    );
    if (server == null || !context.mounted) return;
    final next = [...config.bootstrapServers]..[index] = server;
    onChanged(config.copyWith(bootstrapServers: next));
  }

  Future<void> _delete(BuildContext context, int index) async {
    final l10n = context.l10n;
    if (config.bootstrapServers.length <= 1) {
      await confirmDesktopAction(
        context,
        title: l10n.desktopUpstreamDeleteTitle,
        body: l10n.desktopUpstreamBootstrapKeepOne,
        confirmLabel: l10n.commonConfirm,
        destructive: false,
        showCancel: false,
      );
      return;
    }
    final target = config.bootstrapServers[index];
    final confirmed = await confirmDesktopAction(
      context,
      title: l10n.desktopUpstreamDeleteTitle,
      body: l10n.desktopUpstreamBootstrapDeleteBody(target.name),
      confirmLabel: l10n.commonDelete,
    );
    if (!confirmed || !context.mounted) return;
    onChanged(
      config.copyWith(
        bootstrapServers: [...config.bootstrapServers]..removeAt(index),
      ),
    );
  }

  Future<void> _probe(
    BuildContext context,
    WidgetRef ref,
    DesktopBootstrapServer server,
  ) async {
    final result = await ref
        .read(desktopUpstreamProbeProvider.notifier)
        .test(
          DesktopUpstreamProvider(
            id: 'bootstrap:${server.id}',
            protocol: 'BOOTSTRAP',
            server: server.address,
          ),
        );
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
      semanticLabel: l10n.desktopUpstreamBootstrapTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.link,
            title: l10n.desktopUpstreamBootstrapTitle,
            leading: [
              DashboardChip(
                label: config.bootstrapEnabled
                    ? l10n.desktopUpstreamBootstrapOn
                    : l10n.desktopUpstreamBootstrapOff,
                tone: config.bootstrapEnabled
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
              ),
            ],
            trailing: [
              DashboardSwitch(
                value: config.bootstrapEnabled,
                semanticLabel: l10n.desktopUpstreamBootstrapTitle,
                onChanged: saving
                    ? null
                    : (value) => onChanged(
                        config.copyWith(bootstrapEnabled: value),
                      ),
              ),
              DashboardIconButton(
                glyph: AppGlyphs.addCircle,
                tooltip: l10n.desktopUpstreamBootstrapAdd,
                onPressed: saving ? null : () => _add(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopUpstreamBootstrapBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          if (config.bootstrapServers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n.desktopUpstreamBootstrapEmpty,
                textAlign: TextAlign.center,
                style: DashboardText.label(context),
              ),
            )
          else
            for (var index = 0; index < config.bootstrapServers.length; index++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: index == config.bootstrapServers.length - 1 ? 0 : 8,
                ),
                child: _BootstrapRow(
                  server: config.bootstrapServers[index],
                  probe: probes.results[
                      'bootstrap:${config.bootstrapServers[index].id}'],
                  probing: probes.isBusy(
                    'bootstrap:${config.bootstrapServers[index].id}',
                  ),
                  onTest: saving
                      ? null
                      : () => _probe(
                          context,
                          ref,
                          config.bootstrapServers[index],
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

class _BootstrapRow extends StatelessWidget {
  const _BootstrapRow({
    required this.server,
    required this.probe,
    required this.probing,
    required this.onTest,
    required this.onEdit,
    required this.onDelete,
  });

  final DesktopBootstrapServer server;
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          Row(
            spacing: 4,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      server.name.isEmpty ? server.address : server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardText.rowTitle(context),
                    ),
                    Text(
                      server.address,
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
          Wrap(
            spacing: 8,
            runSpacing: 4,
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

Future<DesktopBootstrapServer?> showBootstrapEditor(
  BuildContext context, {
  DesktopBootstrapServer? editing,
  required int nextIndex,
}) => showFloatingDialog<DesktopBootstrapServer>(
  context: context,
  child: _BootstrapEditor(editing: editing, nextIndex: nextIndex),
);

class _BootstrapEditor extends StatefulWidget {
  const _BootstrapEditor({this.editing, required this.nextIndex});

  final DesktopBootstrapServer? editing;
  final int nextIndex;

  @override
  State<_BootstrapEditor> createState() => _BootstrapEditorState();
}

class _BootstrapEditorState extends State<_BootstrapEditor> {
  late final _name = TextEditingController(text: widget.editing?.name ?? '');
  late final _address = TextEditingController(
    text: widget.editing?.address ?? '223.5.5.5:53',
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final address = _address.text.trim();
    if (name.isEmpty || address.isEmpty) {
      setState(() => _error = context.l10n.desktopUpstreamBootstrapInvalid);
      return;
    }
    popFloatingDialog(
      context,
      DesktopBootstrapServer(
        id: widget.editing?.id ?? 'bootstrap-${widget.nextIndex}',
        name: name,
        address: address,
        weight: widget.editing?.weight ?? 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CommonDialog(
      title: widget.editing == null
          ? l10n.desktopUpstreamBootstrapAddTitle
          : l10n.desktopUpstreamBootstrapEditTitle,
      hasFields: true,
      width: 420,
      actions: [
        TextButton(
          onPressed: () => popFloatingDialog(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(onPressed: _save, child: Text(l10n.commonSave)),
      ],
      child: SizedBox(
        width: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in _bootstrapPresets)
                  TonalButton(
                    size: TonalButtonSize.compact,
                    label: preset.name,
                    onPressed: () => setState(() {
                      _name.text = preset.name;
                      _address.text = preset.address;
                    }),
                  ),
              ],
            ),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.desktopUpstreamBootstrapName,
              ),
              style: AppTextStyle.callout.of(context),
            ),
            TextFormField(
              controller: _address,
              decoration: InputDecoration(
                labelText: l10n.desktopUpstreamBootstrapAddress,
                hintText: '223.5.5.5:53',
              ),
              style: AppTextStyle.callout.of(context),
            ),
            if (_error case final error?)
              Text(
                error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: context.colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
