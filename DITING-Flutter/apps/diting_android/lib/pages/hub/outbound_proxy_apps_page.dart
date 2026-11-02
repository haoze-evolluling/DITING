part of 'outbound_proxy_pages.dart';

/// Proxy app selection (upstream `OutboundProxyAppsScreen`). Single select that writes
/// straight into `OutboundProxyStore`, matching upstream's `singleSelect` with `onSave`.
class OutboundProxyAppsPage extends ConsumerStatefulWidget {
  const OutboundProxyAppsPage({super.key});

  @override
  ConsumerState<OutboundProxyAppsPage> createState() =>
      _OutboundProxyAppsPageState();
}

class _OutboundProxyAppsPageState extends ConsumerState<OutboundProxyAppsPage> {
  final _search = TextEditingController();
  String _query = '';

  /// In-memory only: 1.4.3 `OutboundProxySettingsScreen` passes empty change callbacks here, so the
  /// picker never persisted its filter or sort.
  AppListFilter _filter = AppListFilter.user;
  AppListSort _sort = AppListSort.labelAsc;

  /// Same 250 ms debounce as 1.4.3 `AppPickerScreen`.
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value);
    });
  }

  Future<void> _pick(OutboundProxyConfig config, String packageName) async {
    await ref
        .read(outboundProxyStoreProvider)
        .write(config.copyWith(proxyAppPackage: packageName));
    ref.read(outboundProxyRevisionProvider.notifier).bump();
    if (mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(outboundProxyConfigProvider).value;
    final selected = config?.proxyAppPackage ?? '';
    final snapshot = ref.watch(installedAppsProvider);
    final apps = snapshot.value?.apps ?? const <InstalledApp>[];
    final visible = visibleInstalledApps(
      apps: apps,
      query: _query,
      filter: _filter,
      sort: _sort,
      selected: {selected},
    );
    return CommonScaffold(
      title: context.l10n.outboundAppsTitle,
      menuItems: appListMenuItems(
        l10n: context.l10n,
        filter: _filter,
        sort: _sort,
        onFilterChanged: (value) => setState(() => _filter = value),
        onSortChanged: (value) => setState(() => _sort = value),
      ),
      body: AppListScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                PageIntroCard(text: context.l10n.outboundAppsIntro),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SearchField(
                    controller: _search,
                    onChanged: _onSearchChanged,
                  ),
                ),
                if (snapshot.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CommonCircleLoading()),
                  )
                else if (snapshot.value?.error case final error?)
                  AppListErrorState(error: error),
              ],
            ),
          ),
          if (!snapshot.isLoading && snapshot.value?.error == null)
            ...appListSlivers(
              title: context.l10n.outboundAppsCount(visible.length),
              itemCount: visible.length,
              footer: visible.isEmpty
                  ? (apps.isEmpty ? context.l10n.outboundAppsEmpty : context.l10n.appSelectionNoMatch)
                  : null,
              itemBuilder: (context, index) {
                final app = visible[index];
                final isSelected = selected == app.packageName;
                return ListItem(
                  leading: AppIconAvatar(packageName: app.packageName),
                  title: Text(
                    app.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    app.packageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isSelected ? const SelectionCheck() : null,
                  onTap: config == null
                      ? null
                      : () => _pick(config, app.packageName),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
