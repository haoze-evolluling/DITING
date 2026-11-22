library;

import 'package:diting_android/data/native/flow_bridge.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class FlowConnectionsView extends StatefulWidget {
  const FlowConnectionsView({super.key, required this.rows});

  final List<FlowRow> rows;

  @override
  State<FlowConnectionsView> createState() => _FlowConnectionsViewState();
}

class _FlowConnectionsViewState extends State<FlowConnectionsView> {
  String? _selectedApp;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<FlowRow>>{};
    for (final row in widget.rows) {
      groups.putIfAbsent(row.appLabel, () => []).add(row);
    }
    if (groups.isEmpty) return const SizedBox.shrink();

    final wide = MediaQuery.sizeOf(context).width >= 720;
    final apps = groups.keys.toList();
    final selectedApp = _selectedApp;
    final selected = (selectedApp != null && groups.containsKey(selectedApp))
        ? selectedApp
        : apps.first;
    if (!wide) {
      return Column(
        children: [
          for (final entry in groups.entries)
            _groupSection(entry.key, entry.value),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 280,
          child: generateSection(
            title: context.l10n.flowAppsSection,
            items: [
              for (final app in apps)
                ListItem(
                  leading: const Icon(TablerIcons.list),
                  title: Text(
                    app,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: app == selected
                      ? const Icon(TablerIcons.circle_check)
                      : null,
                  onTap: () => setState(() => _selectedApp = app),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _groupSection(selected, groups[selected]!)),
      ],
    );
  }

  Widget _groupSection(String title, List<FlowRow> rows) {
    return generateSection(
      title: title,
      items: [for (final row in rows) _FlowTile(row: row)],
    );
  }
}

class _FlowTile extends StatelessWidget {
  const _FlowTile({required this.row});

  final FlowRow row;

  @override
  Widget build(BuildContext context) {
    final blocked = row.status == 'failed';
    final color = blocked
        ? context.colorScheme.error
        : context.colorScheme.success;
    return ListItem(
      leading: Icon(
        blocked ? TablerIcons.ban : TablerIcons.circle_check,
        color: color,
      ),
      title: Text(row.hostLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${row.protocol.toUpperCase()} ${row.dstIp}:${row.dstPort} · '
        '↑${_bytes(row.upBytes)} ↓${_bytes(row.downBytes)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        _statusLabel(context.l10n, row.status),
        style: AppTextRole.caption.of(context).copyWith(color: color),
      ),
    );
  }

  static String _bytes(int value) {
    if (value < 1024) return '${value}B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)}KB';
    return '${(value / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  static String _statusLabel(AppL10n l10n, String status) => switch (status) {
    'failed' => l10n.flowStatusFailed,
    'closed' => l10n.flowStatusClosed,
    _ => l10n.flowStatusActive,
  };
}
