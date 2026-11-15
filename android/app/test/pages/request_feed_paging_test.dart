import 'package:diting_android/data/db/dns_query_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_android/state/observability_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// One row per millisecond, newest first, so a timestamp cursor is unambiguous.
List<ObservedRequest> _rows(int count) => [
  for (var index = 0; index < count; index++)
    ObservedRequest.fromDns(
      DnsLogRow(
        id: index,
        timestamp: 1_700_000_000_000 - index,
        queryName: 'host$index.example',
        queryType: 1,
        result: 'PASSED',
        cached: false,
        message: '',
      ),
    ),
];

/// Inclusive cursor paging over an in-memory list, shaped like the SQL the kernel now emits:
/// `WHERE timestamp <= ? ORDER BY timestamp DESC LIMIT 50`.
RequestFeedPageLoader _loader(
  List<ObservedRequest> all,
  List<int?> cursors,
) => (
  ref,
  query, {
  String? packageName,
  int? before,
  bool watch = false,
}) async {
  cursors.add(before);
  final eligible = before == null
      ? all
      : [
          for (final item in all)
            if (item.timestamp <= before) item,
        ];
  final window = eligible.take(requestFeedPageSize + 1).toList(growable: false);
  final hasMore = window.length > requestFeedPageSize;
  final items = hasMore
      ? window.sublist(0, requestFeedPageSize)
      : window;
  return (
    items: items,
    hasMore: hasMore,
    cursor: items.isEmpty ? before : items.last.timestamp,
  );
};

Future<ProviderContainer> _container(RequestFeedPageLoader loader) async {
  final container = ProviderContainer(
    overrides: [requestFeedPageLoaderProvider.overrideWithValue(loader)],
  );
  addTearDown(container.dispose);
  await container.read(requestFeedProvider.future);
  return container;
}

void main() {
  test('首页只读一页，后续页带游标且不重复拉取之前的所有行', () async {
    final cursors = <int?>[];
    final all = _rows(120);
    final container = await _container(_loader(all, cursors));

    expect(
      container.read(requestFeedProvider).requireValue.items,
      hasLength(requestFeedPageSize),
    );
    expect(cursors, [null]);

    await container.read(requestFeedProvider.notifier).loadMore();
    // Second read is bounded by the first page's oldest row, not by an ever-wider window.
    expect(cursors, hasLength(2));
    expect(cursors.last, all[requestFeedPageSize - 1].timestamp);

    final feed = container.read(requestFeedProvider).requireValue;
    expect(feed.items.length, greaterThan(requestFeedPageSize));
    expect(feed.hasMore, isTrue);
  });

  test('游标边界行重复出现时按 key 去重，不会重复渲染', () async {
    final all = _rows(20);
    // A loader that always repeats the boundary row, which is what an inclusive `<=` does.
    var calls = 0;
    final container = await _container((
      ref,
      query, {
      String? packageName,
      int? before,
      bool watch = false,
    }) async {
      calls++;
      final eligible = before == null
          ? all
          : [
              for (final item in all)
                if (item.timestamp <= before) item,
            ];
      // 6 rows a page so the boundary repeat is visible within a small fixture.
      final window = eligible.take(6).toList(growable: false);
      return (
        items: window,
        hasMore: eligible.length > 6,
        cursor: window.isEmpty ? before : window.last.timestamp,
      );
    });

    var previous = container.read(requestFeedProvider).requireValue.items.length;
    for (var i = 0; i < 3; i++) {
      await container.read(requestFeedProvider.notifier).loadMore();
      final items = container.read(requestFeedProvider).requireValue.items;
      expect(items.map((item) => item.key).toSet(), hasLength(items.length));
      expect(items.length, greaterThanOrEqualTo(previous));
      previous = items.length;
    }
    expect(calls, greaterThan(1));
  });

  test('一页只有重复行时停止翻页，不会用同一个游标空转', () async {
    final all = _rows(5);
    var calls = 0;
    final container = await _container((
      ref,
      query, {
      String? packageName,
      int? before,
      bool watch = false,
    }) async {
      calls++;
      return (items: all, hasMore: true, cursor: all.last.timestamp);
    });

    final notifier = container.read(requestFeedProvider.notifier);
    await notifier.loadMore();
    final afterFirst = calls;
    // `hasMore` was reported false by the loader once nothing fresh arrived.
    expect(
      container.read(requestFeedProvider).requireValue.hasMore,
      isFalse,
    );

    await notifier.loadMore();
    expect(calls, afterFirst, reason: '没有新行时不应再请求同一游标');
  });

  test('筛选条件变化会从第一页重来', () async {
    final cursors = <int?>[];
    final all = _rows(120);
    final container = await _container(_loader(all, cursors));

    await container.read(requestFeedProvider.notifier).loadMore();
    expect(container.read(requestFeedProvider).requireValue.items.length,
        greaterThan(requestFeedPageSize));

    cursors.clear();
    container.read(requestFeedQueryProvider.notifier).setStatus(
      RequestStatus.blocked,
    );
    await container.read(requestFeedProvider.future);

    expect(cursors, [null]);
    expect(
      container.read(requestFeedProvider).requireValue.items,
      hasLength(requestFeedPageSize),
    );
  });
}
