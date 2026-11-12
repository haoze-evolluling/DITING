/// Request list (upstream `views/connection/requests.dart`): `http_request_log` + `dns_log`.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:async';

import 'package:diting_android/data/db/dns_query_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_android/pages/observability/domain_detail_parts.dart';
import 'package:diting_android/pages/observability/observability_common.dart';
import 'package:diting_android/routes/observability_routes.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_android/state/log_providers.dart';
import 'package:diting_android/state/observability_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_icon_avatar.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

part 'requests_apps.dart';
part 'requests_detail.dart';
part 'requests_rows.dart';

/// Every app's requests; the menu leads to the per-app pages.
class RequestsPage extends ConsumerWidget {
  const RequestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RequestFeedView(
      title: context.l10n.obsRequestsTitle,
      queryProvider: requestFeedQueryProvider,
      watchFeed: (ref) => ref.watch(requestFeedProvider),
      loadMore: (ref) => ref.read(requestFeedProvider.notifier).loadMore(),
      leadingMenuItems: [
        CommonPopupMenuItem(
          label: context.l10n.obsByApp,
          glyph: AppGlyphs.appsList,
          onPressed: () => context.push(ObservabilityPaths.requestApps),
        ),
        CommonPopupMenuItem(
          label: context.l10n.obsExportLogs,
          glyph: AppGlyphs.export,
          onPressed: () => context.push(ObservabilityPaths.requestExport),
        ),
      ],
    );
  }
}

/// Filterable, paged request list shared by [RequestsPage] and [AppRequestsPage]; each page brings
/// its own query and feed so their filters never leak into each other.
class RequestFeedView extends ConsumerStatefulWidget {
  const RequestFeedView({
    super.key,
    required this.title,
    required this.queryProvider,
    required this.watchFeed,
    required this.loadMore,
    this.packageName,
    this.leadingMenuItems = const [],
  });

  final String title;
  final NotifierProvider<RequestFeedNotifier, RequestFeedQuery> queryProvider;
  /// The global and per-app loaders are different provider types with no shared public supertype,
  /// so the view takes accessors instead of the providers themselves.
  final AsyncValue<RequestFeed> Function(WidgetRef ref) watchFeed;
  final void Function(WidgetRef ref) loadMore;

  /// Set when the list is already narrowed to one app; the detail sheet then hides its link to
  /// the same app page.
  final String? packageName;
  final List<CommonPopupMenuItem> leadingMenuItems;

  @override
  ConsumerState<RequestFeedView> createState() => _RequestFeedViewState();
}

class _RequestFeedViewState extends ConsumerState<RequestFeedView> {
  /// 250 ms search debounce, as upstream: every keystroke would otherwise issue a LIKE query.
  static const _searchDebounce = Duration(milliseconds: 250);

  Timer? _searchTimer;

  /// Distance from the end of the list at which the next page starts loading.
  static const double _loadMoreThreshold = 240;

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  void _onSearch(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () {
      if (!mounted) return;
      ref.read(widget.queryProvider.notifier).setQuery(value.trim());
    });
  }

  void _refresh() => ref.read(dnsLogRevisionProvider.notifier).bump();

  void _resetFilters() {
    ref.read(widget.queryProvider.notifier).reset();
    _searchTimer?.cancel();
  }

  void _openDetail(ObservedRequest request) {
    showSheet<void>(
      context: context,
      builder: (_) => RequestDetailSheet(
        request: request,
        showAppLink: widget.packageName == null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncFeed = widget.watchFeed(ref);
    final query = ref.watch(widget.queryProvider);
    final filterLabel = [
      if (query.source != RequestSource.all) query.source.label,
      if (query.status != RequestStatus.all) query.status.label,
    ].join(' · ');

    return CommonScaffold(
      title: widget.title,
      searchState: AppBarSearchState(onSearch: _onSearch),
      menuItems: [
        ...widget.leadingMenuItems,
        CommonPopupMenuItem(
          label: context.l10n.obsSource,
          glyph: AppGlyphs.filter,
          subItems: [
            for (final source in RequestSource.values)
              CommonPopupMenuItem(
                label: source.label,
                checked: source == query.source,
                onPressed: () =>
                    ref.read(widget.queryProvider.notifier).setSource(source),
              ),
          ],
        ),
        CommonPopupMenuItem(
          label: context.l10n.obsStatus,
          glyph: AppGlyphs.status,
          subItems: [
            for (final status in RequestStatus.values)
              CommonPopupMenuItem(
                label: status.label,
                checked: status == query.status,
                onPressed: () =>
                    ref.read(widget.queryProvider.notifier).setStatus(status),
              ),
          ],
        ),
        CommonPopupMenuItem(
          label: context.l10n.obsRefresh,
          glyph: AppGlyphs.refresh,
          onPressed: _refresh,
        ),
        if (query.source != RequestSource.all ||
            query.status != RequestStatus.all)
          CommonPopupMenuItem(
            label: context.l10n.obsClearFilter,
            glyph: AppGlyphs.reset,
            onPressed: _resetFilters,
          ),
      ],
      body: _buildBody(asyncFeed, filterLabel),
    );
  }

  Widget _buildBody(AsyncValue<RequestFeed> asyncFeed, String filterLabel) {
    // Check hasValue first: a refresh keeps the old value alongside isLoading, and
    // looking at isLoading alone would flash the loading state and lose scroll.
    if (asyncFeed.hasValue) return _body(asyncFeed.requireValue, filterLabel);
    if (asyncFeed.hasError) {
      return ObsFailure(
        label: context.l10n.obsLoadFailed,
        description: '${asyncFeed.error}',
        onRetry: _refresh,
      );
    }
    return ObservabilityLoading(label: context.l10n.obsLoading);
  }

  Widget _body(RequestFeed feed, String filterLabel) {
    final items = feed.items;
    final failed = items
        .where((request) => request.status == RequestStatus.error)
        .length;

    return NullStatusSwitcher(
      isEmpty: items.isEmpty,
      isSearching: ref.read(widget.queryProvider).query.isNotEmpty,
      nullStatus: obsEmpty(
        label: filterLabel.isEmpty ? context.l10n.obsNoRecords : context.l10n.obsNoMatchingRequests,
        description: filterLabel.isEmpty
            ? context.l10n.obsNoRecordsBody
            : context.l10n.obsCurrentFilter(filterLabel),
        illustration: NullStatusIllustration.requests,
        action: FilledButton(
          onPressed: _resetFilters,
          child: Text(context.l10n.obsResetFilter),
        ),
      ),
      child: NotificationListener<ScrollNotification>(
        // 240 px of slack starts the next cursor page before the user hits the end.
        onNotification: (notification) {
          if (notification.metrics.extentAfter < _loadMoreThreshold) {
            _loadMore(feed);
          }
          return false;
        },
        child: PrismListView(
          padding: EdgeInsets.only(top: context.contentTopPadding, bottom: 16),
          // Header + one row per request + footer.
          itemCount: items.length + 2,
          estimatedItemExtent: 92,
          itemBuilder: (context, index) {
            if (index == 0) return ListHeader(title: context.l10n.obsRecordsHeader);
            if (index == items.length + 1) {
              return _FeedFooter(
                label: context.l10n.obsFooterCount(
                  items.length,
                  failed,
                  filterLabel.isEmpty
                      ? ''
                      : context.l10n.obsFooterFilter(filterLabel),
                  feed.hasMore
                      ? context.l10n.obsFooterMore
                      : context.l10n.obsFooterAll,
                ),
                loading: _isLoadingMore(feed),
              );
            }
            final request = items[index - 1];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ItemPositionProvider(
                position: ItemPosition.get(index - 1, items.length),
                child: MemoBuilder(
                  key: ObjectKey(request),
                  inputs: [request],
                  builder: (_) =>
                      RequestRow(request: request, onTap: () => _openDetail(request)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Requests the next cursor page when the list is scrolled near its end.
  ///
  /// [RequestFeed.loadingMore] is the guard: the loader refuses a second request while one is in
  /// flight, so a scroll burst cannot queue the same cursor twice. A failed read surfaces as
  /// [ObsFailure], whose retry restarts from the top.
  void _loadMore(RequestFeed feed) {
    if (!feed.hasMore || feed.loadingMore) return;
    widget.loadMore(ref);
  }

  bool _isLoadingMore(RequestFeed feed) => feed.loadingMore;
}

/// Footer that doubles as the pagination indicator: a spinner while the next page is being read,
/// the count once it has landed.
class _FeedFooter extends StatelessWidget {
  const _FeedFooter({required this.label, required this.loading});

  final String label;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
      child: Row(
        spacing: 8,
        children: [
          if (loading) const CommonCircleLoading(size: 14),
          Expanded(child: Text(label, style: context.listCaptionStyle)),
        ],
      ),
    );
  }
}
