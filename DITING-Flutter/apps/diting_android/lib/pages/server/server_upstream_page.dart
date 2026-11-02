import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/server/dns_server_config.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/pages/server/server_actions.dart';
import 'package:diting_android/pages/server/server_upstream_dialog.dart';
import 'package:diting_android/state/server_status_providers.dart';
import 'package:diting_android/state/server_upstream_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Server mode "upstream server" tab (upstream `server/ui/DnsServersScreen.kt`), segmented
/// by protocol. A selection writes `diting_dns_mode_prefs/selected_upstream_id`, effective
/// after a restart. No latency sort: a single upstream would make it a fake control.
class ServerUpstreamPage extends ConsumerStatefulWidget {
  const ServerUpstreamPage({super.key});

  @override
  ConsumerState<ServerUpstreamPage> createState() => _ServerUpstreamPageState();
}

class _ServerUpstreamPageState extends ConsumerState<ServerUpstreamPage> {
  DnsProtocol _protocol = DnsProtocol.dns;

  Future<void> _select(ServerUpstream upstream) async {
    ref.read(serverSelectedUpstreamProvider.notifier).select(upstream.id);
    final running = ref.read(serverStatusProvider) == ServerStatus.running;
    if (!mounted) {
      return;
    }
    showServerHint(
      context,
      running
          ? context.l10n.serverSwitched(upstream.name)
          : context.l10n.serverSelected(upstream.name),
    );
  }

  /// Adds (when [existing] is null) or edits a custom upstream. Validation failures stay in
  /// the dialog with field-level hints; a second message here would duplicate the error.
  Future<void> _edit(ServerUpstream? existing) async {
    final result = await showFloatingDialog<ServerUpstream>(
      context: context,
      child: UpstreamDialog(initial: existing, protocol: _protocol),
    );
    if (result == null || !mounted) {
      return;
    }
    final actions = ref.read(serverUpstreamActionsProvider);
    final saved = existing == null
        ? actions.add(
            name: result.name,
            protocol: result.protocol,
            address: result.address,
            port: result.port,
          )
        : (actions.update(result) ? result : null);
    if (saved == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    // Switch to the new entry's protocol segment, otherwise it stays out of sight.
    setState(() => _protocol = saved.protocol);
    showServerHint(
      context,
      existing == null
          ? context.l10n.serverAdded(saved.name)
          : context.l10n.serverSaved(saved.name),
    );
  }

  /// Deletes a custom upstream. [ServerUpstreamActions.remove] falls back to the first
  /// built-in entry when the deleted one was selected.
  Future<void> _delete(ServerUpstream upstream) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.serverDeleteConfirm(upstream.name),
        destructive: true,
        hasFields: false,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.configCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.configDelete),
          ),
        ],
        child: Text(
          '${upstream.endpointLabel}\n\n${context.l10n.serverDeleteBody}',
        ),
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final removed = ref.read(serverUpstreamActionsProvider).remove(upstream.id);
    if (removed && mounted) {
      showServerHint(context, context.l10n.serverDeleted(upstream.name));
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(serverUpstreamListProvider);
    final selected = ref.watch(serverSelectedUpstreamProvider);
    final selectedId = selected.id;
    final visible = [
      for (final upstream in all)
        if (upstream.protocol == _protocol) upstream,
    ];
    final presets = [
      for (final upstream in visible)
        if (!_isCustom(upstream)) upstream,
    ];
    final customs = [
      for (final upstream in visible)
        if (_isCustom(upstream)) upstream,
    ];
    return CommonScaffold(
      title: context.l10n.serverUpstreamTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.serverAddCustom,
          onPressed: () => _edit(null),
          icon: const GlyphIcon(AppGlyphs.addCircle),
        ),
      ],
      body: PageBody(
        children: [
          // Upstream's activeItemText, above the protocol segments because it describes the
          // page-wide selection and stays visible when switching to DoH.
          PageIntroText(
            text:
                context.l10n.serverCurrentUpstream(
                  _protocolLabel(selected.protocol),
                  selected.name,
                ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: SegmentedControl<DnsProtocol>(
              segments: const [
                (DnsProtocol.dns, 'DNS'),
                (DnsProtocol.doh, 'DoH'),
                (DnsProtocol.dot, 'DoT'),
              ],
              value: _protocol,
              onChanged: (value) => setState(() => _protocol = value),
            ),
          ),
          generateSection(
            title: context.l10n.serverBuiltinProviders,
            items: [
              if (presets.isEmpty)
                ListItem(
                  title: Text(context.l10n.serverNoBuiltin),
                  leading: GlyphIcon(AppGlyphs.info),
                )
              else
                for (final upstream in presets)
                  _UpstreamRow(
                    upstream: upstream,
                    selected: upstream.id == selectedId,
                    onTap: () => _select(upstream),
                  ),
            ],
          ),
          generateSection(
            title: context.l10n.serverCustomProviders,
            items: [
              if (customs.isEmpty)
                ListItem(
                  title: Text(context.l10n.serverNoCustom),
                  subtitle: Text(context.l10n.serverNoCustomBody),
                  leading: const GlyphIcon(AppGlyphs.addCircle),
                  trailing: const GlyphIcon(AppGlyphs.chevronForward, size: 20),
                  onTap: () => _edit(null),
                )
              else
                for (final upstream in customs)
                  _UpstreamRow(
                    upstream: upstream,
                    selected: upstream.id == selectedId,
                    onTap: () => _select(upstream),
                    onEdit: () => _edit(upstream),
                    onDelete: () => _delete(upstream),
                  ),
              if (customs.isNotEmpty)
                ListItem(
                  title: Text(context.l10n.serverAddCustom),
                  leading: const GlyphIcon(AppGlyphs.addCircle),
                  onTap: () => _edit(null),
                ),
            ],
            footer:
                context.l10n.serverUpstreamFooter,
          ),
        ],
      ),
    );
  }

  /// Custom entries come from `custom_upstreams` with no `isCustom` flag; built-in ids
  /// carry a `preset_` prefix (same convention as upstream `DnsUpstreamServer.PRESETS`).
  static bool _isCustom(ServerUpstream upstream) =>
      !upstream.id.startsWith('preset_');

  /// Protocol display name. `DnsProtocol.storageValue` is the upper-case stored form, so
  /// showing it directly would read "(DOH)" instead of the legacy "DoH".
  static String _protocolLabel(DnsProtocol protocol) => switch (protocol) {
    DnsProtocol.dns => 'DNS',
    DnsProtocol.doh => 'DoH',
    DnsProtocol.dot => 'DoT',
  };
}

class _UpstreamRow extends StatelessWidget {
  const _UpstreamRow({
    required this.upstream,
    required this.selected,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final ServerUpstream upstream;
  final bool selected;
  final VoidCallback onTap;

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: GlyphIcon(
        upstream.protocol == DnsProtocol.doh ? AppGlyphs.lock : AppGlyphs.dns,
        size: 20,
      ),
      title: Text(upstream.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        upstream.endpointLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onEdit == null && onDelete == null
          ? (selected ? const SelectionCheck() : null)
          : Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                if (selected) const SelectionCheck(),
                _RowMenu(
                  name: upstream.name,
                  onEdit: onEdit!,
                  onDelete: onDelete!,
                ),
              ],
            ),
      onTap: onTap,
    );
  }
}

/// Trailing "more" menu with edit / delete. Tapping pushes [CommonPopupRoute] directly: a
/// `ContextMenuRegion` long-press sits under the `ListItem.onTap`, which swallows the icon tap.
class _RowMenu extends StatelessWidget {
  const _RowMenu({
    required this.name,
    required this.onEdit,
    required this.onDelete,
  });

  final String name;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  void _open(BuildContext context) {
    final box = context.findRenderObject();
    final navigator = Navigator.maybeOf(context);
    final navigatorBox = navigator?.context.findRenderObject();
    if (box is! RenderBox ||
        navigator == null ||
        navigatorBox is! RenderBox ||
        !box.hasSize) {
      return;
    }
    final point = navigatorBox.globalToLocal(
      box.localToGlobal(box.size.bottomLeft(Offset.zero)),
    );
    navigator.push(
      CommonPopupRoute<void>(
        barrierLabel: MaterialLocalizations.of(context)
            .modalBarrierDismissLabel,
        placement: PopupPlacement.belowPoint,
        elevated: ElevatedSurfaceTheme.isIn(context),
        anchorOf: () => point & Size.zero,
        builder: (_) => CommonPopupMenu(
          items: [
            CommonPopupMenuItem(
              label: context.l10n.serverEditName(name),
              glyph: AppGlyphs.edit,
              onPressed: onEdit,
            ),
            CommonPopupMenuItem(
              label: context.l10n.serverDeleteName(name),
              glyph: AppGlyphs.delete,
              danger: true,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context),
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: GlyphIcon(AppGlyphs.more, size: 20),
      ),
    );
  }
}
