/// N4 实时连接视图的状态：合并引擎的增量快照为一份按最近活跃排序的连接表。
library;

import 'package:diting_android/data/native/flow_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final flowBridgeProvider = Provider<FlowBridge>((ref) => const FlowBridge());

class FlowViewState {
  const FlowViewState({
    this.rowsMap = const {},
    this.nextSeq = 0,
    this.truncated = false,
    this.error,
  });

  final Map<String, FlowRow> rowsMap;
  final int nextSeq;
  final bool truncated;
  final String? error;

  int get total => rowsMap.length;

  List<FlowRow> get rows {
    final list = rowsMap.values.toList();
    list.sort((a, b) => b.lastSeenMs.compareTo(a.lastSeenMs));
    return list;
  }
}

class FlowViewNotifier extends Notifier<FlowViewState> {
  @override
  FlowViewState build() => const FlowViewState();

  /// Pulls the delta since the last cursor (or the whole table when [full]) and merges it in.
  Future<void> refresh({bool full = false}) async {
    final since = full ? 0 : state.nextSeq;
    final snapshot = await ref
        .read(flowBridgeProvider)
        .snapshot(sinceSeq: since, limit: 500);
    final map = full
        ? <String, FlowRow>{}
        : Map<String, FlowRow>.from(state.rowsMap);
    for (final row in snapshot.rows) {
      final existing = map[row.key];
      if (existing == null || row.seq >= existing.seq) {
        map[row.key] = row;
      }
    }
    state = FlowViewState(
      rowsMap: map,
      nextSeq: snapshot.nextSeq,
      truncated: snapshot.truncated,
    );
  }

  void clear() => state = const FlowViewState();
}

final flowViewProvider = NotifierProvider<FlowViewNotifier, FlowViewState>(
  FlowViewNotifier.new,
);
