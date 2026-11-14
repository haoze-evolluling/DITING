/// U2 全局搜索的状态：一个查询串 + 由其派生的结果列表。
library;

import 'package:diting_android/data/global_search_index.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GlobalSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) {
    if (state == value) return;
    state = value;
  }

  void clear() => set('');
}

final globalSearchQueryProvider =
    NotifierProvider<GlobalSearchQueryNotifier, String>(
      GlobalSearchQueryNotifier.new,
    );

/// 结果由查询派生；空查询直接返回空，避免每帧重建整个索引。
final globalSearchResultsProvider = Provider<List<GlobalSearchEntry>>((ref) {
  final query = ref.watch(globalSearchQueryProvider);
  if (query.trim().isEmpty) return const [];
  return filterGlobalSearch(buildGlobalSearchIndex(currentL10n), query);
});
