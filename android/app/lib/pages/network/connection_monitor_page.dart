library;

import 'dart:async';

import 'package:diting_android/pages/network/app_insights_view.dart';
import 'package:diting_android/pages/network/flow_connections_view.dart';
import 'package:diting_android/state/app_insights_providers.dart';
import 'package:diting_android/state/flow_providers.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

enum ConnectionMonitorTab { live, insights }

class ConnectionMonitorPage extends ConsumerStatefulWidget {
  const ConnectionMonitorPage({super.key});

  @override
  ConsumerState<ConnectionMonitorPage> createState() =>
      _ConnectionMonitorPageState();
}

class _ConnectionMonitorPageState extends ConsumerState<ConnectionMonitorPage> {
  Timer? _timer;
  var _tab = ConnectionMonitorTab.live;

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
    final l10n = context.l10n;
    final rows = ref.watch(flowViewProvider).rows;
    final actions = [
      IconButton(
        tooltip: l10n.flowRefresh,
        onPressed: () => _refresh(full: true),
        icon: const Icon(TablerIcons.refresh),
      ),
    ];
    return CommonScaffold(
      title: l10n.flowTitle,
      actions: actions,
      body: PageBody(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: SegmentedControl<ConnectionMonitorTab>(
              segments: [
                (ConnectionMonitorTab.live, l10n.flowLiveTab),
                (ConnectionMonitorTab.insights, l10n.appInsightsTitle),
              ],
              value: _tab,
              onChanged: (value) => setState(() => _tab = value),
            ),
          ),
          if (_tab == ConnectionMonitorTab.live)
            FlowConnectionsView(rows: rows)
          else
            AppInsightsView(
              reports: ref.watch(appReportsProvider),
              map: ref.watch(connectionMapProvider),
            ),
        ],
      ),
    );
  }
}
