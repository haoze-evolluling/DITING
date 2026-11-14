/// N4 实时连接视图：按 应用 → 域名 → 远端 展示正在发生的连接（协议 / 状态 / 上下行）。
library;

import 'dart:async';

import 'package:diting_android/data/native/flow_bridge.dart';
import 'package:diting_android/state/flow_providers.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class FlowPage extends ConsumerStatefulWidget {
  const FlowPage({super.key});

  @override
  ConsumerState<FlowPage> createState() => _FlowPageState();
}

class _FlowPageState extends ConsumerState<FlowPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refresh(full: true);
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh({bool full = false}) {
    if (!mounted) return;
    ref.read(flowViewProvider.notifier).refresh(full: full);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(flowViewProvider);
    final groups = <String, List<FlowRow>>{};
    for (final row in state.rows) {
      groups.putIfAbsent(row.appLabel, () => []).add(row);
    }
    return CommonScaffold(
      title: context.l10n.flowTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.flowRefresh,
          onPressed: () => _refresh(full: true),
          icon: const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: PageBody(
        children: [
          if (state.rows.isEmpty)
            PageIntroCard(text: context.l10n.flowEmptyBody)
          else
            for (final group in groups.entries)
              generateSection(
                title: group.key,
                items: [
                  for (final row in group.value) _FlowTile(row: row),
                ],
              ),
        ],
      ),
    );
  }
}

class _FlowTile extends StatelessWidget {
  const _FlowTile({required this.row});

  final FlowRow row;

  @override
  Widget build(BuildContext context) {
    final blocked = row.status == 'failed';
    final color = blocked ? context.colorScheme.error : context.colorScheme.success;
    return ListItem(
      leading: GlyphIcon(
        blocked ? AppGlyphs.block : AppGlyphs.checkCircle,
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
        style: AppTextStyle.caption1.of(context).copyWith(color: color),
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
