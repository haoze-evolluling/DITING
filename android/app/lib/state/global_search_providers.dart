library;

import 'package:diting_android/data/global_search_index.dart';
import 'package:diting_android/app/l10n/l10n.dart';
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

final globalSearchResultsProvider = Provider<List<GlobalSearchEntry>>((ref) {
  final query = ref.watch(globalSearchQueryProvider);
  if (query.trim().isEmpty) return const [];
  return filterGlobalSearch(buildGlobalSearchIndex(currentL10n), query);
});
