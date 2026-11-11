part of 'http_inspection_page.dart';

class HttpInspectionAppsPage extends ConsumerStatefulWidget {
  const HttpInspectionAppsPage({super.key});

  @override
  ConsumerState<HttpInspectionAppsPage> createState() =>
      _HttpInspectionAppsPageState();
}

class _HttpInspectionAppsPageState
    extends ConsumerState<HttpInspectionAppsPage> {
  final _search = TextEditingController();
  String _query = '';

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

  /// Every change is persisted immediately, since the parent page reads the same keys; the
  /// master switch is left alone, matching `saveHttpInspectionApps`.
  void _write(Set<String> packages) {
    final settings = ref.read(legacySettingsProvider);
    settings.setHttpInspectionApps(
      packages: packages,
      enabled: settings.httpInspectionEnabled,
    );
    if (packages.isNotEmpty) {
      settings.setExcludedPackages(
        settings.excludedPackages.difference(packages),
      );
      settings.setBlockedApps(
        packages: settings.blockedAppPackages.difference(packages),
        enabled: settings.blockedAppsEnabled,
      );
      final allowlist = settings.appAllowlistRules;
      if (allowlist.keys.any(packages.contains)) {
        settings.setAppAllowlistRules({
          for (final entry in allowlist.entries)
            if (!packages.contains(entry.key)) entry.key: entry.value,
        });
      }
    }
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(legacySettingsProvider);
    final selected = settings.httpInspectionPackages;
    final filter = AppListFilter.fromStorageValue(
      settings.httpInspectionAppsFilterRaw,
    );
    final sort = AppListSort.fromStorageValue(
      settings.httpInspectionAppsSortRaw,
    );
    final snapshot = ref.watch(installedAppsProvider);
    final apps = snapshot.value?.apps ?? const <InstalledApp>[];
    final visible = visibleInstalledApps(
      apps: apps,
      query: _query,
      filter: filter,
      sort: sort,
      selected: selected,
    );
    final visiblePackages = {for (final app in visible) app.packageName};
    return CommonScaffold(
      title: context.l10n.httpInspAppsTitle,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.selectAll,
          tooltip: context.l10n.httpInspSelectVisible,
          onPressed: visible.isEmpty
              ? null
              : () => _write({...selected, ...visiblePackages}),
        ),
        IconButtonData(
          glyph: AppGlyphs.deselect,
          tooltip: context.l10n.httpInspDeselectVisible,
          onPressed: visible.isEmpty
              ? null
              : () => _write(selected.difference(visiblePackages)),
        ),
      ],
      menuItems: appListMenuItems(
        l10n: context.l10n,
        filter: filter,
        sort: sort,
        onFilterChanged: (value) {
          settings.setHttpInspectionAppsFilterRaw(value.storageValue);
          ref.read(legacySettingsRevisionProvider.notifier).bump();
        },
        onSortChanged: (value) {
          settings.setHttpInspectionAppsSortRaw(value.storageValue);
          ref.read(legacySettingsRevisionProvider.notifier).bump();
        },
        onSelectAll: () => _write({...selected, ...visiblePackages}),
        onClear: () => _write(const {}),
        onInvert: () => _write(
          selected
              .difference(visiblePackages)
              .union(visiblePackages.difference(selected)),
        ),
      ),
      body: AppListScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                PageIntroCard(text: context.l10n.httpInspAppsIntro),
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
              title: context.l10n.httpInspAppsCount(
                selected.length,
                visible.length,
              ),
              itemCount: visible.length,
              footer: visible.isEmpty
                  ? (apps.isEmpty ? context.l10n.appSelectionNoAppsAvailable : context.l10n.appSelectionNoMatch)
                  : null,
              itemBuilder: (context, index) {
                final app = visible[index];
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
                  trailing: CommonCheckBox(
                    value: selected.contains(app.packageName),
                    isCircle: true,
                    onChanged: (_) => _toggle(selected, app.packageName),
                  ),
                  onTap: () => _toggle(selected, app.packageName),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  void _toggle(Set<String> selected, String packageName) {
    final next = {...selected};
    if (!next.remove(packageName)) {
      next.add(packageName);
    }
    _write(next);
  }
}
