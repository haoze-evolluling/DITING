/// The recognised LAN clients, one block per address: its name, its access state, how much it asked
/// and when, plus the alias / whitelist / blocklist actions.
///
/// The old desktop console's `ClientsPanel.vue` table is the blueprint; the rows are blocks instead
/// of a table so a 390 px window does not need horizontal scrolling.
library;

import 'dart:async';

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_traffic_models.dart';
import 'package:diting/desktop/data/api/desktop_traffic_providers.dart';
import 'package:diting/desktop/pages/hub/widgets/filter_common.dart';
import 'package:diting/desktop/pages/traffic/desktop_client_groups_page.dart';
import 'package:diting/desktop/widgets/desktop_feedback.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class DesktopClientListCard extends ConsumerWidget {
  const DesktopClientListCard({
    super.key,
    required this.clients,
    required this.access,
    required this.saving,
    required this.loading,
    required this.onRefresh,
  });

  final List<DesktopClient> clients;
  final DesktopAccessControl access;
  final bool saving;
  final bool loading;
  final VoidCallback onRefresh;

  Future<void> _editAlias(
    BuildContext context,
    WidgetRef ref,
    DesktopClient client,
  ) async {
    final l10n = context.l10n;
    final name = await showFloatingDialog<String>(
      context: context,
      child: _AliasDialog(client: client),
    );
    if (name == null || !context.mounted) return;
    final error = await ref
        .read(desktopTrafficProvider.notifier)
        .setAlias(client.ip, name);
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (name.isEmpty
                ? l10n.desktopTrafficAliasCleared(client.ip)
                : l10n.desktopTrafficAliasSaved(client.ip))
          : l10n.desktopTrafficSaveFailed(error.message),
    );
  }

  Future<void> _toggleAllowed(
    BuildContext context,
    WidgetRef ref,
    DesktopClient client,
  ) async {
    final l10n = context.l10n;
    final allowed = [...access.allowed];
    final blocked = [
      for (final ip in access.blocked)
        if (ip != client.ip) ip,
    ];
    final wasAllowed = allowed.remove(client.ip);
    if (!wasAllowed) allowed.add(client.ip);
    final error = await ref
        .read(desktopTrafficProvider.notifier)
        .saveAccess(DesktopAccessControl(allowed: allowed, blocked: blocked));
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (wasAllowed
                ? l10n.desktopTrafficAllowedRemoved(client.ip)
                : l10n.desktopTrafficAllowedAdded(client.ip))
          : l10n.desktopTrafficSaveFailed(error.message),
    );
  }

  Future<void> _toggleBlocked(
    BuildContext context,
    WidgetRef ref,
    DesktopClient client,
  ) async {
    final l10n = context.l10n;
    final blocked = [...access.blocked];
    final allowed = [
      for (final ip in access.allowed)
        if (ip != client.ip) ip,
    ];
    final wasBlocked = blocked.remove(client.ip);
    if (!wasBlocked) blocked.add(client.ip);
    final error = await ref
        .read(desktopTrafficProvider.notifier)
        .saveAccess(DesktopAccessControl(allowed: allowed, blocked: blocked));
    if (!context.mounted) return;
    showDesktopMessage(
      context,
      error == null
          ? (wasBlocked
                ? l10n.desktopTrafficBlockedRemoved(client.ip)
                : l10n.desktopTrafficBlockedAdded(client.ip))
          : l10n.desktopTrafficSaveFailed(error.message),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return DashboardCard(
      semanticLabel: l10n.desktopTrafficClientsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.devices,
            title: l10n.desktopTrafficClientsTitle,
            leading: [
              DashboardChip(
                label: l10n.desktopTrafficClientCount(clients.length),
                tone: DashboardChipTone.idle,
              ),
            ],
            trailing: [
              SizedBox(
                height: 28,
                child: DashboardIconButton(
                  glyph: AppGlyphs.layers,
                  tooltip: l10n.desktopGroupsOpen,
                  size: 28,
                  glyphSize: 15,
                  onPressed: () => context.push(DesktopClientGroupsPage.path),
                ),
              ),
              SizedBox(
                height: 28,
                child: DashboardIconButton(
                  glyph: AppGlyphs.refresh,
                  tooltip: l10n.desktopTrafficRefresh,
                  size: 28,
                  glyphSize: 15,
                  onPressed: loading ? null : onRefresh,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopTrafficClientsBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          if (clients.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                l10n.desktopTrafficClientsEmpty,
                textAlign: TextAlign.center,
                style: DashboardText.label(context),
              ),
            )
          else
            for (final client in clients)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ClientRow(
                  client: client,
                  access: access,
                  saving: saving,
                  onAlias: () =>
                      unawaited(_editAlias(context, ref, client)),
                  onAllowed: () =>
                      unawaited(_toggleAllowed(context, ref, client)),
                  onBlocked: () =>
                      unawaited(_toggleBlocked(context, ref, client)),
                ),
              ),
        ],
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({
    required this.client,
    required this.access,
    required this.saving,
    required this.onAlias,
    required this.onAllowed,
    required this.onBlocked,
  });

  final DesktopClient client;
  final DesktopAccessControl access;
  final bool saving;
  final VoidCallback onAlias;
  final VoidCallback onAllowed;
  final VoidCallback onBlocked;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final blocked = access.blocks(client.ip);
    final allowed = access.allows(client.ip);
    final chip = blocked
        ? DashboardChip(
            label: l10n.desktopTrafficStateBlocked,
            tone: DashboardChipTone.warn,
            dot: true,
          )
        : allowed
        ? DashboardChip(
            label: l10n.desktopTrafficStateAllowed,
            tone: DashboardChipTone.ok,
            dot: true,
          )
        : access.allowed.isNotEmpty
        ? DashboardChip(
            label: l10n.desktopTrafficStateNotAllowed,
            tone: DashboardChipTone.warn,
          )
        : DashboardChip(
            label: l10n.desktopTrafficStateOpen,
            tone: DashboardChipTone.idle,
          );
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                client.ip,
                style: DashboardText.rowTitle(context).toMonospace,
              ),
              chip,
            ],
          ),
          Text(
            client.name.isEmpty
                ? l10n.desktopTrafficClientUnnamed
                : client.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(
              context,
              color: client.name.isEmpty
                  ? context.colorScheme.onSurfaceVariant
                  : null,
            ),
          ),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Text(
                l10n.desktopTrafficClientQueries(client.queryCount),
                style: DashboardText.label(context),
              ),
              Text(
                client.lastSeen <= 0
                    ? l10n.desktopTrafficClientNever
                    : l10n.desktopTrafficClientLastSeen(
                        desktopMonthDayTime(
                          DateTime.fromMillisecondsSinceEpoch(
                            client.lastSeen * 1000,
                          ),
                        ),
                      ),
                style: DashboardText.label(context),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              TextButton(
                onPressed: saving ? null : onAlias,
                child: Text(l10n.desktopTrafficAlias),
              ),
              TextButton(
                onPressed: saving ? null : onAllowed,
                child: Text(
                  allowed
                      ? l10n.desktopTrafficAllowedRemove
                      : l10n.desktopTrafficAllowedAdd,
                ),
              ),
              TextButton(
                onPressed: saving ? null : onBlocked,
                child: Text(
                  blocked
                      ? l10n.desktopTrafficBlockedRemove
                      : l10n.desktopTrafficBlockedAdd,
                  style: TextStyle(
                    color: blocked ? context.colorScheme.error : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AliasDialog extends StatefulWidget {
  const _AliasDialog({required this.client});

  final DesktopClient client;

  @override
  State<_AliasDialog> createState() => _AliasDialogState();
}

class _AliasDialogState extends State<_AliasDialog> {
  late final _name = TextEditingController(text: widget.client.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CommonDialog(
      title: l10n.desktopTrafficAliasTitle,
      hasFields: true,
      width: 460,
      actions: [
        TextButton(
          onPressed: () => popFloatingDialog(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => popFloatingDialog(context, _name.text.trim()),
          child: Text(l10n.desktopTrafficAliasSave),
        ),
      ],
      child: SizedBox(
        width: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Text(
              widget.client.ip,
              style: DashboardText.rowTitle(context).toMonospace,
            ),
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.desktopTrafficAliasField,
                hintText: l10n.desktopTrafficAliasHint,
              ),
            ),
            Text(
              l10n.desktopTrafficAliasBody,
              style: DashboardText.label(context),
            ),
          ],
        ),
      ),
    );
  }
}
