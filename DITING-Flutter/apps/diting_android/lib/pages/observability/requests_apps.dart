part of 'requests_page.dart';

/// Display name of a package: the installed label when known, the package name otherwise
/// (uninstalled apps keep their history).
String _appLabelOf(WidgetRef ref, String packageName) {
  final apps = ref.watch(installedAppListProvider) ?? const [];
  for (final app in apps) {
    if (app.packageName == packageName && app.label.isNotEmpty) {
      return app.label;
    }
  }
  return packageName;
}

/// Apps that appear in the request log, most requests first; a row opens [AppRequestsPage].
class RequestAppsPage extends ConsumerStatefulWidget {
  const RequestAppsPage({super.key});

  @override
  ConsumerState<RequestAppsPage> createState() => _RequestAppsPageState();
}

class _RequestAppsPageState extends ConsumerState<RequestAppsPage> {
  /// Filtered in Dart: the list is one row per app, small enough to hold whole.
  String _query = '';

  void _refresh() => ref.read(dnsLogRevisionProvider.notifier).bump();

  @override
  Widget build(BuildContext context) {
    final asyncApps = ref.watch(requestAppCountsProvider);
    return CommonScaffold(
      title: context.l10n.obsAppsTitle,
      searchState: AppBarSearchState(
        onSearch: (value) => setState(() => _query = value.trim()),
      ),
      menuItems: [
        CommonPopupMenuItem(
          label: context.l10n.obsRefresh,
          glyph: AppGlyphs.refresh,
          onPressed: _refresh,
        ),
      ],
      body: switch (asyncApps) {
        AsyncValue(:final value?) => _body(value),
        AsyncValue(:final error?) => ObsFailure(
          label: context.l10n.obsLoadFailed,
          description: '$error',
          onRetry: _refresh,
        ),
        _ => ObservabilityLoading(label: context.l10n.obsLoading),
      },
    );
  }

  Widget _body(List<AppRequestCount> apps) {
    final needle = _query.toLowerCase();
    final shown = needle.isEmpty
        ? apps
        : [
            for (final app in apps)
              if (app.packageName.toLowerCase().contains(needle) ||
                  _appLabelOf(
                    ref,
                    app.packageName,
                  ).toLowerCase().contains(needle))
                app,
          ];

    return NullStatusSwitcher(
      isEmpty: shown.isEmpty,
      isSearching: _query.isNotEmpty,
      nullStatus: obsEmpty(
        label: _query.isEmpty
            ? context.l10n.obsAppsEmpty
            : context.l10n.obsNoMatchingRequests,
        description: _query.isEmpty ? context.l10n.obsAppsEmptyBody : null,
        illustration: NullStatusIllustration.requests,
      ),
      child: ListView.builder(
        padding: EdgeInsets.only(top: context.contentTopPadding, bottom: 16),
        // Header + one row per app + footer.
        itemCount: shown.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) return ListHeader(title: context.l10n.obsAppsHeader);
          if (index == shown.length + 1) {
            return ListFooter(text: context.l10n.obsAppsFooter);
          }
          final app = shown[index - 1];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ItemPositionProvider(
              position: ItemPosition.get(index - 1, shown.length),
              child: _RequestAppRow(app: app),
            ),
          );
        },
      ),
    );
  }
}

class _RequestAppRow extends ConsumerWidget {
  const _RequestAppRow({required this.app});

  final AppRequestCount app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final label = _appLabelOf(ref, app.packageName);
    return ListItem(
      leading: AppIconAvatar(packageName: app.packageName),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        label == app.packageName
            ? context.l10n.obsAppRequestCount(app.count)
            : '${app.packageName} · ${context.l10n.obsAppRequestCount(app.count)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: GlyphIcon(
        AppGlyphs.chevronForward,
        size: 18,
        color: colorScheme.onSurfaceVariant,
      ),
      onTap: () =>
          context.push(ObservabilityPaths.appRequests(app.packageName)),
    );
  }
}

/// Requests of one app, with the same source, status and keyword filters as [RequestsPage].
class AppRequestsPage extends ConsumerWidget {
  const AppRequestsPage({super.key, required this.packageName});

  final String packageName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RequestFeedView(
      title: _appLabelOf(ref, packageName),
      queryProvider: appRequestFeedQueryProvider(packageName),
      feedProvider: appRequestFeedProvider(packageName),
      packageName: packageName,
    );
  }
}
