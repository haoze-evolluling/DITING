import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/apps_bridge.dart';
import 'package:diting_android/data/native/outbound_proxy_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/pages/hub/outbound_proxy_pages.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_android/state/outbound_proxy_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_icon_avatar.dart';
import 'package:diting_android/widgets/app_list_error_state.dart';
import 'package:diting_android/widgets/app_list_view.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Multi-select of the apps routed through the outbound proxy in per-app scope. Every toggle is
/// written straight to `OutboundProxyStore`, like the single-select proxy app picker; the
/// tunnel picks the list up on its next start.
class OutboundProxyTargetsPage extends ConsumerStatefulWidget {
  const OutboundProxyTargetsPage({super.key});

  @override
  ConsumerState<OutboundProxyTargetsPage> createState() =>
      _OutboundProxyTargetsPageState();
}

class _OutboundProxyTargetsPageState
    extends ConsumerState<OutboundProxyTargetsPage> {
  final _search = TextEditingController();
  String _query = '';
  AppListFilter _filter = AppListFilter.user;
  AppListSort _sort = AppListSort.labelAsc;
  Timer? _debounce;

  /// Local copy, seeded once: rapid toggles must not each start from a stale provider value.
  Set<String>? _selected;

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

  Future<void> _write(OutboundProxyConfig config, Set<String> next) async {
    setState(() => _selected = next);
    await ref
        .read(outboundProxyStoreProvider)
        .write(config.copyWith(targetPackages: {...next}));
    ref.read(outboundProxyRevisionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(outboundProxyConfigProvider).value;
    final excluded = ref.watch(legacySettingsProvider).excludedPackages;
    final selected = _selected ??= config == null
        ? null
        : {...config.targetPackages};
    final snapshot = ref.watch(installedAppsProvider);
    // Apps outside the TUN can never be proxied, so offering them would be a silent no-op.
    final apps = [
      for (final app in snapshot.value?.apps ?? const <InstalledApp>[])
        if (app.packageName != ditingSelfPackage &&
            app.packageName != config?.proxyAppPackage &&
            !excluded.contains(app.packageName))
          app,
    ];
    final current = selected ?? const <String>{};
    final visible = visibleInstalledApps(
      apps: apps,
      query: _query,
      filter: _filter,
      sort: _sort,
      selected: current,
    );
    void update(Set<String> Function(Set<String>) change) {
      if (config != null) _write(config, change({...current}));
    }

    return CommonScaffold(
      title: context.l10n.outboundTargetsTitle,
      menuItems: appListMenuItems(
        l10n: context.l10n,
        filter: _filter,
        sort: _sort,
        onFilterChanged: (value) => setState(() => _filter = value),
        onSortChanged: (value) => setState(() => _sort = value),
        onSelectAll: () =>
            update((s) => s..addAll(visible.map((a) => a.packageName))),
        onClear: () => update((s) => s..clear()),
        onInvert: () => update((s) {
          for (final app in visible) {
            if (!s.remove(app.packageName)) s.add(app.packageName);
          }
          return s;
        }),
      ),
      body: AppListScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                PageIntroCard(text: context.l10n.outboundTargetsIntro),
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
              title: context.l10n.appSelectionCount('${current.length}'),
              itemCount: visible.length,
              footer: visible.isEmpty
                  ? (apps.isEmpty
                        ? context.l10n.appSelectionNoAppsAvailable
                        : context.l10n.appSelectionNoMatch)
                  : null,
              itemBuilder: (context, index) {
                final app = visible[index];
                void toggle() => update(
                  (s) => s.remove(app.packageName) ? s : (s..add(app.packageName)),
                );
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
                    value: current.contains(app.packageName),
                    isCircle: true,
                    onChanged: (_) => toggle(),
                  ),
                  onTap: config == null ? null : toggle,
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
