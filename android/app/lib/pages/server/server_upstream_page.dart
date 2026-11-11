import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/server/dns_server_config.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/pages/server/server_actions.dart';
import 'package:diting_android/pages/server/server_upstream_dialog.dart';
import 'package:diting_android/state/server_resolution_providers.dart';
import 'package:diting_android/state/server_status_providers.dart';
import 'package:diting_android/state/server_upstream_providers.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Server mode "upstream server" tab (upstream `server/ui/DnsServersScreen.kt`), segmented by
/// protocol. The resolution mode decides whether a tap selects the single upstream or toggles one
/// candidate in a race list; the same four modes the tunnel uses, on the same engine scheduler.
class ServerUpstreamPage extends ConsumerStatefulWidget {
  const ServerUpstreamPage({super.key});

  @override
  ConsumerState<ServerUpstreamPage> createState() => _ServerUpstreamPageState();
}

class _ServerUpstreamPageState extends ConsumerState<ServerUpstreamPage> {
  DnsProtocol _protocol = DnsProtocol.dns;

  /// Single mode: the tap picks the sole upstream. Effective after a restart.
  Future<void> _selectSingle(ServerUpstream upstream) async {
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

  /// Race modes: tapping toggles membership, never dropping below the two-provider minimum.
  void _toggleRace(ServerUpstream upstream) {
    final before = ref.read(serverRaceProvidersProvider);
    if (before.contains(upstream.id) &&
        before.length <= ServerRaceProvidersNotifier.minCount) {
      showServerHint(context, context.l10n.resolutionMinProviders);
      return;
    }
    ref.read(serverRaceProvidersProvider.notifier).toggle(upstream.id);
  }

  /// Swaps a row with its neighbour inside [visibleIds] (the current protocol group), so the
  /// arrows move what the user sees and other protocols keep their stored slots.
  void _move(List<String> visibleIds, String id, int delta) {
    final index = visibleIds.indexOf(id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= visibleIds.length) {
      return;
    }
    final other = visibleIds[target];
    final next = ref.read(serverRaceProvidersProvider).toList();
    final from = next.indexOf(id);
    final to = next.indexOf(other);
    if (from < 0 || to < 0) {
      return;
    }
    next[from] = other;
    next[to] = id;
    ref.read(serverRaceProvidersProvider.notifier).reorder(next);
  }

  void _showModePicker(ResolutionMode current) {
    showFloatingDialog<void>(
      context: context,
      child: CommonDialog(
        title: context.l10n.resolutionPickerTitle,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ResolutionMode.values)
              ListItem(
                leading: GlyphIcon(_modeGlyph(mode), size: 20),
                title: Text(mode.label(context.l10n)),
                subtitle: Text(_modeDescription(mode, context.l10n)),
                trailing: mode == current ? const SelectionCheck() : null,
                onTap: () {
                  ref.read(serverResolutionModeProvider.notifier).select(mode);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
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
    final mode = ref.watch(serverResolutionModeProvider);
    final selected = ref.watch(serverSelectedUpstreamProvider);
    final raceIds = ref.watch(serverRaceProvidersProvider);
    final single = mode.isSingle;
    final visible = [
      for (final upstream in all)
        if (upstream.protocol == _protocol) upstream,
    ];
    // Race modes render one combined list in stored order (engine attempt order), then the rest.
    final ordered = [
      for (final id in raceIds)
        ...all.where(
          (upstream) => upstream.id == id && upstream.protocol == _protocol,
        ),
    ];
    final rest = [
      for (final upstream in visible)
        if (!raceIds.contains(upstream.id)) upstream,
    ];
    final orderedIds = [for (final upstream in ordered) upstream.id];
    bool isSelected(ServerUpstream upstream) =>
        single ? upstream.id == selected.id : raceIds.contains(upstream.id);
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: CommonCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                spacing: 12,
                children: [
                  GlyphIcon(
                    _modeGlyph(mode),
                    size: 24,
                    color: context.colorScheme.primary,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(mode.label(context.l10n), style: context.listTitleStyle),
                        Text(
                          _modeDescription(mode, context.l10n),
                          style: context.listSubtitleStyle,
                        ),
                      ],
                    ),
                  ),
                  const GlyphIcon(AppGlyphs.chevronForward, size: 18),
                ],
              ),
              onPressed: () => _showModePicker(mode),
            ),
          ),
          // Upstream's activeItemText; describes the page-wide selection so it stays visible when
          // switching to DoH.
          PageIntroText(
            text: single
                ? context.l10n.serverCurrentUpstream(
                    _protocolLabel(selected.protocol),
                    selected.name,
                  )
                : context.l10n.resolutionRaceHint(raceIds.length),
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
          if (single)
            ..._singleSections(context, visible, selected)
          else
            _raceSection(
              context,
              mode: mode,
              rows: [...ordered, ...rest],
              isSelected: isSelected,
              orderButtons: mode == ResolutionMode.primaryBackup
                  ? (upstream) => _OrderButtons(
                      onUp: () => _move(orderedIds, upstream.id, -1),
                      onDown: () => _move(orderedIds, upstream.id, 1),
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  /// Single mode keeps the built-in / custom split and the selection semantics of the old page.
  List<Widget> _singleSections(
    BuildContext context,
    List<ServerUpstream> visible,
    ServerUpstream selected,
  ) {
    final presets = [
      for (final upstream in visible)
        if (!_isCustom(upstream)) upstream,
    ];
    final customs = [
      for (final upstream in visible)
        if (_isCustom(upstream)) upstream,
    ];
    bool isSelected(ServerUpstream upstream) => upstream.id == selected.id;
    return [
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
                selected: isSelected(upstream),
                onTap: () => _selectSingle(upstream),
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
                selected: isSelected(upstream),
                onTap: () => _selectSingle(upstream),
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
        footer: context.l10n.serverUpstreamFooter,
      ),
    ];
  }

  /// Race modes render one list so primary-to-backup order is unambiguous across protocols.
  Widget _raceSection(
    BuildContext context, {
    required ResolutionMode mode,
    required List<ServerUpstream> rows,
    required bool Function(ServerUpstream) isSelected,
    required Widget? Function(ServerUpstream)? orderButtons,
  }) {
    final title = switch (mode) {
      ResolutionMode.smart => context.l10n.resolutionSectionSmart,
      ResolutionMode.parallel => context.l10n.resolutionSectionParallel,
      ResolutionMode.primaryBackup => context.l10n.resolutionSectionBackup,
      ResolutionMode.single => context.l10n.resolutionSectionSingle,
    };
    return generateSection(
      title: title,
      footer: context.l10n.serverUpstreamFooter,
      items: [
        if (rows.isEmpty)
          ListItem(
            title: Text(context.l10n.resolutionNoProviders),
            leading: GlyphIcon(AppGlyphs.info),
          )
        else
          for (final upstream in rows)
            _UpstreamRow(
              upstream: upstream,
              selected: isSelected(upstream),
              onTap: () => _toggleRace(upstream),
              onEdit: _isCustom(upstream) ? () => _edit(upstream) : null,
              onDelete: _isCustom(upstream) ? () => _delete(upstream) : null,
              orderButtons: isSelected(upstream)
                  ? orderButtons?.call(upstream)
                  : null,
            ),
        ListItem(
          title: Text(context.l10n.serverAddCustom),
          leading: const GlyphIcon(AppGlyphs.addCircle),
          onTap: () => _edit(null),
        ),
      ],
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

  static Glyph _modeGlyph(ResolutionMode mode) => switch (mode) {
    ResolutionMode.single => AppGlyphs.dns,
    ResolutionMode.smart => AppGlyphs.sparkle,
    ResolutionMode.parallel => AppGlyphs.speed,
    ResolutionMode.primaryBackup => AppGlyphs.swap,
  };

  static String _modeDescription(ResolutionMode mode, AppL10n l10n) =>
      switch (mode) {
        ResolutionMode.single => l10n.resolutionSingleDesc,
        ResolutionMode.smart => l10n.resolutionSmartDesc,
        ResolutionMode.parallel => l10n.resolutionParallelDesc,
        ResolutionMode.primaryBackup => l10n.resolutionPrimaryBackupDesc,
      };
}

class _UpstreamRow extends StatelessWidget {
  const _UpstreamRow({
    required this.upstream,
    required this.selected,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.orderButtons,
  });

  final ServerUpstream upstream;
  final bool selected;
  final VoidCallback onTap;

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final Widget? orderButtons;

  @override
  Widget build(BuildContext context) {
    final trailing = <Widget>[
      ?orderButtons,
      if (onEdit != null && onDelete != null)
        _RowMenu(name: upstream.name, onEdit: onEdit!, onDelete: onDelete!),
    ];
    return ListItem(
      leading: GlyphIcon(
        selected
            ? AppGlyphs.checkCircle
            : (upstream.protocol == DnsProtocol.doh
                  ? AppGlyphs.lock
                  : AppGlyphs.dns),
        size: 20,
      ),
      title: Text(upstream.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        upstream.endpointLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing.isEmpty
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: trailing,
            ),
      onTap: onTap,
    );
  }
}

class _OrderButtons extends StatelessWidget {
  const _OrderButtons({required this.onUp, required this.onDown});

  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: context.l10n.resolutionMoveUp,
          onPressed: onUp,
          icon: const GlyphIcon(AppGlyphs.arrowUp, size: 18),
        ),
        IconButton(
          tooltip: context.l10n.resolutionMoveDown,
          onPressed: onDown,
          icon: const GlyphIcon(AppGlyphs.arrowDown, size: 18),
        ),
      ],
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
