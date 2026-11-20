library;

import 'package:diting_android/data/global_search_index.dart';
import 'package:diting_android/state/work_mode_providers.dart';
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

final globalSearchResultsProvider = Provider<List<GlobalSearchEntry>>((ref) {
  final query = ref.watch(globalSearchQueryProvider);
  if (query.trim().isEmpty) return const [];
  final express = ref.watch(workModeProvider) == AppWorkMode.express;
  return filterGlobalSearch(
    buildGlobalSearchIndex(currentL10n, express: express),
    query,
  );
});
