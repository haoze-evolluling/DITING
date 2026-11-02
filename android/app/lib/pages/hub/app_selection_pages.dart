import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/apps_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_icon_avatar.dart';
import 'package:diting_android/widgets/app_list_error_state.dart';
import 'package:diting_android/widgets/app_list_view.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_android/widgets/unsaved_changes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Blocked apps (upstream `BlockedAppsScreen`). Writes `blocked_app_packages` and
/// `blocked_apps_enabled` into `dns_vpn_prefs`; normal mode hands the UIDs to the Go engine.
class BlockedAppsPage extends ConsumerWidget {
  const BlockedAppsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(legacySettingsProvider);
    return _AppSelectionScaffold(
      title: context.l10n.appBlockTitle,
      info: context.l10n.appBlockInfo,
      enableToggleTitle: context.l10n.appBlockToggle,
      enableToggleEmptyHint: context.l10n.appBlockToggleEmpty,
      selectionTitle: context.l10n.appBlockSelection,
      icon: AppGlyphs.wifiOff,
      selected: settings.blockedAppPackages,
      enabled: settings.blockedAppsEnabled,
      filter: AppListFilter.fromStorageValue(settings.blockedAppsFilterRaw),
      sort: AppListSort.fromStorageValue(settings.blockedAppsSortRaw),
      onFilterChanged: (value) {
        settings.setBlockedAppsFilterRaw(value.storageValue);
        ref.read(legacySettingsRevisionProvider.notifier).bump();
      },
      onSortChanged: (value) {
        settings.setBlockedAppsSortRaw(value.storageValue);
        ref.read(legacySettingsRevisionProvider.notifier).bump();
      },
      onSave: (packages, enabled) => _saveBlocked(ref, packages, enabled),
    );
  }

  /// Saves the list and drops those apps from the other three, as upstream does in one save:
  /// missing one leaves an app both blocked and excluded, decided by engine check order.
  static void _saveBlocked(WidgetRef ref, Set<String> packages, bool enabled) {
    final settings = ref.read(legacySettingsProvider);
    settings.setBlockedApps(packages: packages, enabled: enabled);
    _dropOverlaps(settings, packages, _Owner.blocked);
    ref.read(legacySettingsRevisionProvider.notifier).bump();
  }
}

/// Excluded apps (upstream `ExcludedAppsScreen`). Writes `excluded_app_packages`: these use
/// the system DNS and skip filtering, caching, logging and statistics. Same data as
/// `/apps`, different entry point.
class ExcludedAppsPage extends ConsumerWidget {
  const ExcludedAppsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(legacySettingsProvider);
    return _AppSelectionScaffold(
      title: context.l10n.appExcludeTitle,
      info: context.l10n.appExcludeInfo,
      selectionTitle: context.l10n.appExcludeSelection,
      icon: AppGlyphs.appsList,
      selected: settings.excludedPackages,
      enabled: true,
      showToggle: false,
      filter: AppListFilter.fromStorageValue(settings.excludedAppsFilterRaw),
      sort: AppListSort.fromStorageValue(settings.excludedAppsSortRaw),
      onFilterChanged: (value) {
        settings.setExcludedAppsFilterRaw(value.storageValue);
        ref.read(legacySettingsRevisionProvider.notifier).bump();
      },
      onSortChanged: (value) {
        settings.setExcludedAppsSortRaw(value.storageValue);
        ref.read(legacySettingsRevisionProvider.notifier).bump();
      },
      onSave: (packages, _) {
        settings.setExcludedPackages(packages);
        _dropOverlaps(settings, packages, _Owner.excluded);
        ref.read(legacySettingsRevisionProvider.notifier).bump();
      },
    );
  }
}

/// Which list was just written, so the exclusivity pass can skip it. Passed in because
/// `LegacySettings` reads through to the store, making `difference` empty after the write.
enum _Owner { blocked, excluded }

/// Removes the apps just written to one list from the other three. One shared copy:
/// upstream repeated it per page and one copy missed `app_allowlist_rules_json`.
void _dropOverlaps(
  LegacySettings settings,
  Set<String> packages,
  _Owner owner,
) {
  if (packages.isEmpty) {
    return;
  }
  if (owner != _Owner.excluded) {
    settings.setExcludedPackages(
      settings.excludedPackages.difference(packages),
    );
  }
  if (owner != _Owner.blocked) {
    settings.setBlockedApps(
      packages: settings.blockedAppPackages.difference(packages),
      enabled: settings.blockedAppsEnabled,
    );
  }
  final inspection = settings.httpInspectionPackages.difference(packages);
  settings.setHttpInspectionApps(
    packages: inspection,
    // Clearing the list must also clear the master switch: an enabled switch with no
    // targets is skipped by the engine while the UI still shows it on.
    enabled: settings.httpInspectionEnabled && inspection.isNotEmpty,
  );
  final allowlist = settings.appAllowlistRules;
  if (allowlist.keys.any(packages.contains)) {
    settings.setAppAllowlistRules({
      for (final entry in allowlist.entries)
        if (!packages.contains(entry.key)) entry.key: entry.value,
    });
  }
}

class _AppSelectionScaffold extends ConsumerStatefulWidget {
  const _AppSelectionScaffold({
    required this.title,
    required this.info,
    required this.selectionTitle,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onSave,
    required this.filter,
    required this.sort,
    required this.onFilterChanged,
    required this.onSortChanged,
    this.enableToggleTitle,
    this.enableToggleEmptyHint,
    this.showToggle = true,
  });

  final String title;
  final String info;
  final String selectionTitle;
  final Glyph icon;

  final Set<String> selected;
  final bool enabled;
  final bool showToggle;
  final String? enableToggleTitle;
  final String? enableToggleEmptyHint;
  final void Function(Set<String> packages, bool enabled) onSave;

  /// Filter and sort come from the page's own legacy preference keys, so the menu shows the same
  /// choice the stored list had on the next open.
  final AppListFilter filter;
  final AppListSort sort;
  final ValueChanged<AppListFilter> onFilterChanged;
  final ValueChanged<AppListSort> onSortChanged;

  @override
  ConsumerState<_AppSelectionScaffold> createState() =>
      _AppSelectionScaffoldState();
}

class _AppSelectionScaffoldState extends ConsumerState<_AppSelectionScaffold> {
  final _search = TextEditingController();

  Set<String> _initial = const {};
  Set<String> _selected = const {};
  bool _synced = false;
  late bool _enabled = widget.enabled;
  String _query = '';

  /// Same 250 ms debounce as 1.4.3 `AppPickerScreen`, so typing does not re-filter several hundred
  /// apps on every keystroke.
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

  /// Prefs are the only source of truth: a changed stored value discards the local draft,
  /// otherwise saving would resurrect entries another page just removed.
  void _sync(Set<String> persisted) {
    if (!_synced) {
      _synced = true;
      _initial = {...persisted};
      _selected = {...persisted};
      return;
    }
    if (!_sameSet(persisted, _initial)) {
      _initial = {...persisted};
      _selected = {...persisted};
    }
  }

  void _save() {
    widget.onSave({..._selected}, _enabled);
    setState(() {
      _initial = {..._selected};
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(context.l10n.appSelectionSaved),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// True while the draft differs from what is stored. Drives both the save button and the
  /// "save before leaving?" guard.
  bool get _dirty =>
      _enabled != widget.enabled || !_sameSet(_selected, _initial);

  /// Asked when the user leaves with pending changes, from the title-bar arrow and from the system
  /// back gesture alike. Saving here is the same write as the save button.
  Future<bool> _confirmLeave() async {
    final choice = await showUnsavedChangesDialog(
      context,
      title: context.l10n.appSelectionSaveTitle,
      message: context.l10n.appSelectionSaveBody(widget.title),
    );
    if (!mounted) {
      return false;
    }
    switch (choice) {
      case UnsavedChangesChoice.cancel:
        return false;
      case UnsavedChangesChoice.discard:
        return true;
      case UnsavedChangesChoice.save:
        _save();
        return true;
    }
  }

  void _toggle(String packageName) {
    setState(() {
      if (!_selected.remove(packageName)) {
        _selected.add(packageName);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _sync(widget.selected);
    final snapshot = ref.watch(installedAppsProvider);
    final apps = snapshot.value?.apps ?? const <InstalledApp>[];
    // Filter and sort come from the page's own legacy preference keys, so the choice survives a
    // restart exactly as the 1.4.3 screens did.
    final visible = visibleInstalledApps(
      apps: apps,
      query: _query,
      filter: widget.filter,
      sort: widget.sort,
      selected: _selected,
    );
    final dirty = _dirty;
    return UnsavedChangesScope(
      hasUnsavedChanges: () => _dirty,
      onResolve: _confirmLeave,
      child: CommonScaffold(
        title: widget.title,
        menuItems: appListMenuItems(
          l10n: context.l10n,
          filter: widget.filter,
          sort: widget.sort,
          onFilterChanged: widget.onFilterChanged,
          onSortChanged: widget.onSortChanged,
          onSelectAll: () => _selectAll(visible),
          onClear: () => setState(() => _selected = <String>{}),
          onInvert: () => _invert(visible),
        ),
        body: AppListScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  if (widget.showToggle && widget.enableToggleTitle != null)
                    generateSection(
                      title: context.l10n.appSelectionSwitch,
                      items: [
                        ListItem.toggle(
                          leading: const GlyphIcon(AppGlyphs.wifiOff),
                          title: Text(widget.enableToggleTitle!),
                          subtitle: Text(
                            _selected.isEmpty
                                ? (widget.enableToggleEmptyHint ?? context.l10n.appSelectionNoAppsYet)
                                : context.l10n.appSelectionCount(
                                    '${_selected.length}',
                                  ),
                          ),
                          value: _enabled,
                          onChanged: (value) =>
                              setState(() => _enabled = value),
                        ),
                      ],
                    ),
                  PageIntroCard(text: widget.info),
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
                title: '${widget.selectionTitle}（${_selected.length}）',
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
                      value: _selected.contains(app.packageName),
                      isCircle: true,
                      onChanged: (_) => _toggle(app.packageName),
                    ),
                    onTap: () => _toggle(app.packageName),
                  );
                },
              ),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: TonalButton(
                      label: context.l10n.appSelectionSave,
                      onPressed: dirty ? _save : null,
                    ),
                  ),
                  ListFooter(
                    text: apps.isEmpty
                        ? context.l10n.appSelectionNothingRead
                        : context.l10n.appSelectionExclusiveNote,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectAll(List<InstalledApp> visible) {
    setState(() {
      _selected = {..._selected, for (final app in visible) app.packageName};
    });
  }

  void _invert(List<InstalledApp> visible) {
    setState(() {
      final next = {..._selected};
      for (final app in visible) {
        if (!next.remove(app.packageName)) next.add(app.packageName);
      }
      _selected = next;
    });
  }

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}
