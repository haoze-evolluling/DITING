library;

import 'package:diting_android/data/global_search_index.dart';
import 'package:diting_android/router.dart';
import 'package:diting_android/routes/standalone_routes.dart';
import 'package:diting_android/state/global_search_providers.dart';
import 'package:diting_android/widgets/empty_state.dart';
import 'package:diting_android/widgets/glyph_lookup.dart';
import 'package:diting_android/widgets/nav_entry_row.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class GlobalSearchPage extends ConsumerWidget {
  const GlobalSearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(globalSearchQueryProvider);
    final results = ref.watch(globalSearchResultsProvider);
    return CommonScaffold(
      title: context.l10n.searchTitle,
      body: AppBarClearance(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SearchField(
                autofocus: true,
                hintText: context.l10n.searchHint,
                glyph: AppGlyphs.search,
                onChanged: (value) =>
                    ref.read(globalSearchQueryProvider.notifier).set(value),
              ),
            ),
            Expanded(child: _results(context, query, results)),
          ],
        ),
      ),
    );
  }

  Widget _results(
    BuildContext context,
    String query,
    List<GlobalSearchEntry> results,
  ) {
    if (query.trim().isEmpty) {
      return _emptyState(
        context.l10n.searchEmptyTitle,
        context.l10n.searchEmptyBody,
      );
    }
    if (results.isEmpty) {
      return _emptyState(context.l10n.searchNoResults, context.l10n.searchHint);
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final group in _group(results))
          generateSection(
            title: group.key,
            items: [
              for (final entry in group.value)
                NavEntryRow(
                  glyph: glyphByName(entry.glyphName),
                  title: entry.title,
                  subtitle: entry.subtitle.isEmpty ? null : entry.subtitle,
                  subtitleMaxLines: 1,
                  onPressed: () => _open(context, entry),
                ),
            ],
          ),
      ],
    );
  }

  List<MapEntry<String, List<GlobalSearchEntry>>> _group(
    List<GlobalSearchEntry> results,
  ) {
    final groups = <String, List<GlobalSearchEntry>>{};
    for (final entry in results) {
      groups.putIfAbsent(entry.group, () => []).add(entry);
    }
    return groups.entries.toList(growable: false);
  }

  Widget _emptyState(String title, String body) {
    return ListView(
      padding: const EdgeInsets.only(top: 32, bottom: 24),
      children: [
        EmptyStateBox(
          child: NullStatus(
            label: title,
            description: body,
            illustration: NullStatusIllustration.search,
          ),
        ),
      ],
    );
  }

  void _open(BuildContext context, GlobalSearchEntry entry) {
    if (pushStandalone(context, entry.route)) return;
    openLocation(context, entry.route);
  }
}
