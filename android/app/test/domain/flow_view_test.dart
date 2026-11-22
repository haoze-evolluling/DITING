import 'package:diting_android/data/native/flow_bridge.dart';
import 'package:diting_android/state/flow_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

FlowRow _row({
  required String dstIp,
  required int seq,
  int uid = 1,
  String status = 'active',
}) => FlowRow.fromJson({
  'protocol': 'tcp',
  'srcIp': '10.0.0.2',
  'srcPort': 40000,
  'dstIp': dstIp,
  'dstPort': 443,
  'uid': uid,
  'package': 'com.example',
  'domain': '',
  'upBytes': 10,
  'downBytes': 20,
  'status': status,
  'firstSeenMs': 1,
  'lastSeenMs': seq,
  'seq': seq,
})!;

class _FakeBridge implements FlowBridge {
  _FakeBridge(this.snapshots);

  final List<FlowSnapshot> snapshots;
  int calls = 0;

  @override
  Future<FlowSnapshot> snapshot({int sinceSeq = 0, int limit = 500}) async {
    final index = calls < snapshots.length ? calls : snapshots.length - 1;
    calls++;
    return snapshots[index];
  }
}

void main() {
  test('FlowSnapshot parses the engine JSON', () {
    final snapshot = FlowSnapshot.fromJson(
      '{"baseSeq":0,"nextSeq":5,"total":1,"truncated":false,"sessions":['
      '{"protocol":"tcp","srcIp":"10.0.0.2","srcPort":40000,"dstIp":"1.1.1.1",'
      '"dstPort":443,"uid":9,"package":"com.a","domain":"a.com","upBytes":10,'
      '"downBytes":20,"status":"active","firstSeenMs":1,"lastSeenMs":2,"seq":5}]}',
    );
    expect(snapshot.nextSeq, 5);
    expect(snapshot.rows.single.domain, 'a.com');
    expect(snapshot.rows.single.hostLabel, 'a.com');
    expect(snapshot.rows.single.appLabel, 'com.a');
  });

  test('empty payload decodes to an empty snapshot', () {
    expect(FlowSnapshot.fromJson('{}').rows, isEmpty);
  });

  test('FlowRow falls back to IP and uid when labels are missing', () {
    final row = _row(dstIp: '8.8.8.8', seq: 1, uid: 42);
    expect(row.hostLabel, '8.8.8.8');
    expect(row.appLabel, 'com.example');
  });

  test('refresh merges incremental snapshots by key', () async {
    final first = FlowSnapshot(
      baseSeq: 0,
      nextSeq: 1,
      total: 1,
      truncated: false,
      rows: [_row(dstIp: '1.1.1.1', seq: 1)],
    );
    final second = FlowSnapshot(
      baseSeq: 1,
      nextSeq: 2,
      total: 1,
      truncated: false,
      rows: [_row(dstIp: '2.2.2.2', seq: 2)],
    );
    final container = ProviderContainer(
      overrides: [flowBridgeProvider.overrideWithValue(_FakeBridge([first, second]))],
    );
    addTearDown(container.dispose);

    final notifier = container.read(flowViewProvider.notifier);
    await notifier.refresh(full: true);
    expect(container.read(flowViewProvider).total, 1);
    await notifier.refresh();
    expect(container.read(flowViewProvider).total, 2);
    expect(container.read(flowViewProvider).nextSeq, 2);
  });
}
