/// U2 全局搜索/命令面板页面：一个搜索框 + 过滤后的功能与命令列表，点条目直达。
library;

import 'package:diting_android/data/global_search_index.dart';
import 'package:diting_android/router.dart';
import 'package:diting_android/routes/standalone_routes.dart';
import 'package:diting_android/state/global_search_providers.dart';
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
      return _centered(
        context.l10n.searchEmptyTitle,
        context.l10n.searchEmptyBody,
      );
    }
    if (results.isEmpty) {
      return _centered(context.l10n.searchNoResults, context.l10n.searchHint);
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final entry = results[index];
        return ListItem(
          leading: const GlyphIcon(AppGlyphs.search),
          title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            entry.subtitle.isEmpty
                ? entry.group
                : '${entry.group} · ${entry.subtitle}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _open(context, entry),
        );
      },
    );
  }

  Widget _centered(String title, String body) {
    return Builder(
      builder: (context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              const GlyphIcon(AppGlyphs.search, size: 28),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, GlobalSearchEntry entry) {
    // 标签页类目标以全屏页打开；其余正常 push，与功能中心的跳转语义一致。
    if (pushStandalone(context, entry.route)) return;
    openLocation(context, entry.route);
  }
}
