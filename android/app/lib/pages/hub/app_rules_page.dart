// ignore_for_file: sort_child_properties_last
import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/apps_bridge.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/pages/hub/app_rules_store.dart';
import 'package:diting_android/state/app_rules_providers.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_list_error_state.dart';
import 'package:diting_android/widgets/app_list_view.dart';
import 'package:diting_android/widgets/section_slivers.dart';
import 'package:diting_android/widgets/unsaved_changes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

part 'app_rules_detail.dart';

/// Per-app rules (upstream `AppRuleManagementScreen`): master switch, search and configured
/// apps; picking an app swaps to the detail panel within the same route.
class AppRulesPage extends ConsumerStatefulWidget {
  const AppRulesPage({super.key});

  @override
  ConsumerState<AppRulesPage> createState() => _AppRulesPageState();
}

class _AppRulesPageState extends ConsumerState<AppRulesPage> {
  static const _searchDebounce = Duration(milliseconds: 250);

  final _search = TextEditingController();
  Timer? _debounce;

  String _query = '';

  String? _selected;

  AppRulesDraft? _draft;

  String? _lastKey;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () {
      if (!mounted) {
        return;
      }
      setState(() => _query = value.trim().toLowerCase());
    });
  }

  /// Rebuilds the draft from prefs when another page changed the keys. `/apps` deletes apps from
  /// `app_allowlist_rules_json`, and a stale draft would write a removed allow rule back on save.
  AppRulesDraft _draftOf(LegacySettings settings) {
    final key = appRulesKey(
      settings.appAllowlistEnabled,
      settings.appAllowlistRules,
    );
    if (_draft == null || (key != _lastKey && key != _draft!.baselineKey)) {
      _draft = AppRulesDraft.load(settings);
      _lastKey = key;
    }
    return _draft!;
  }

  void _save() {
    final draft = _draft;
    if (draft == null) {
      return;
    }
    saveAppRules(ref, draft);
    setState(() {
      draft.commit();
      _lastKey = draft.baselineKey;
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(context.l10n.appRulesSaved),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(legacySettingsProvider);
    final draft = _draftOf(settings);
    final snapshot = ref.watch(installedAppsProvider);
    final apps = snapshot.value?.apps ?? const <InstalledApp>[];
    // Fall back to the list when the selected app disappears after uninstall. Only a local
    // field is set: scheduling a frame from `build` is not allowed.
    final app = _selected == null
        ? null
        : apps.where((item) => item.packageName == _selected).firstOrNull;
    final showing = app != null ? _selected : null;
    return PopScope(
      canPop: showing == null && !draft.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }
        // Back inside the page walks out of the detail panel first; only leaving the page asks
        // about the pending rules.
        if (showing != null) {
          setState(() => _selected = null);
          return;
        }
        if (!await _confirmLeave(draft)) {
          return;
        }
        if (mounted) {
          Navigator.of(this.context).pop();
        }
      },
      child: app == null
          ? _buildList(context, draft, snapshot, settings)
          : _buildDetail(context, draft, app),
    );
  }

  /// Same question as the blocked/excluded pickers: the draft here is also saved by an explicit
  /// button, so leaving without it would silently drop the edits.
  Future<bool> _confirmLeave(AppRulesDraft draft) async {
    final choice = await showUnsavedChangesDialog(
      context,
      title: context.l10n.commonSaveChangesTitle,
      message: context.l10n.commonSaveChangesMessageFor(
        context.l10n.hubAppRules,
      ),
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

  Widget _buildList(
    BuildContext context,
    AppRulesDraft draft,
    AsyncValue<InstalledAppsSnapshot> snapshot,
    LegacySettings settings,
  ) {
    final apps = snapshot.value?.apps ?? const <InstalledApp>[];
    final filter = AppListFilter.fromStorageValue(
      settings.appAllowlistFilterRaw,
    );
    final sort = AppListSort.fromStorageValue(settings.appAllowlistSortRaw);
    final visible = appRulesVisibleApps(
      apps: apps,
      query: _query,
      filter: filter,
      sort: sort,
      draft: draft,
    );
    final hasAllowlist = draft.configuredApps > 0;
    return CommonScaffold(
      title: context.l10n.hubAppRules,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.broom,
          tooltip: context.l10n.appRulesClearAllTooltip,
          onPressed: hasAllowlist ? () => _clearAll(draft) : null,
        ),
      ],
      menuItems: [
        CommonPopupMenuItem(
          label: context.l10n.commonFilter,
          glyph: AppGlyphs.filter,
          subItems: [
            for (final option in AppListFilter.values)
              CommonPopupMenuItem(
                label: option.label(context.l10n),
                checked: option == filter,
                onPressed: () {
                  settings.setAppAllowlistFilterRaw(option.storageValue);
                  ref.read(legacySettingsRevisionProvider.notifier).bump();
                },
              ),
          ],
        ),
        CommonPopupMenuItem(
          label: context.l10n.uiSort,
          glyph: AppGlyphs.sort,
          subItems: [
            for (final option in AppListSort.values)
              CommonPopupMenuItem(
                label: option.label(context.l10n),
                checked: option == sort,
                onPressed: () {
                  settings.setAppAllowlistSortRaw(option.storageValue);
                  ref.read(legacySettingsRevisionProvider.notifier).bump();
                },
              ),
          ],
        ),
        CommonPopupMenuItem(
          label: context.l10n.commonSave,
          glyph: AppGlyphs.checkCircle,
          onPressed: draft.dirty ? _save : null,
        ),
      ],
      body: AppListScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                generateSection(
                  title: context.l10n.appRulesMasterSection,
                  items: [
                    ListItem.toggle(
                      leading: const GlyphIcon(AppGlyphs.verified),
                      title: Text(context.l10n.appRulesMasterToggle),
                      subtitle: Text(
                        draft.configuredApps == 0
                            ? context.l10n.appRulesNoConfigured
                            : context.l10n.appRulesConfiguredSummary(
                                draft.configuredApps,
                                draft.totalDomains,
                              ),
                      ),
                      value: draft.master,
                      onChanged: (value) =>
                          setState(() => draft.master = value),
                    ),
                  ],
                  footer: context.l10n.appRulesMasterFooter,
                ),
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
                  AppListErrorState(error: error, minHeight: 280),
              ],
            ),
          ),
          if (!snapshot.isLoading && snapshot.value?.error == null)
            ...appListSlivers(
              title: context.l10n.appRulesAppsCount(visible.length),
              itemCount: visible.length,
              footer: visible.isEmpty
                  ? (apps.isEmpty ? context.l10n.appRulesNoConfigurableApps : context.l10n.appSelectionNoMatch)
                  : null,
              itemBuilder: (context, index) {
                final item = visible[index];
                return AppRuleAppRow(
                  app: item,
                  domainCount: draft.domainsOf(item.packageName).length,
                  onTap: () => setState(() => _selected = item.packageName),
                );
              },
            ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: TonalButton(
                    label: context.l10n.commonSave,
                    onPressed: draft.dirty ? _save : null,
                  ),
                ),
                ListFooter(
                  text: apps.isEmpty
                      ? context.l10n.appRulesFooterNoApps
                      : context.l10n.appRulesFooterSave,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetail(
    BuildContext context,
    AppRulesDraft draft,
    InstalledApp app,
  ) {
    final domains = draft.domainsOf(app.packageName);
    final rules = ref.watch(appScopedRulesProvider(app.packageName));
    return CommonScaffold(
      title: app.label,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.add,
          tooltip: context.l10n.appRulesAddAllowDomain,
          onPressed: () => _addDomain(draft, app.packageName),
        ),
      ],
      body: SliverPageBody(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                generateSection(
                  title: context.l10n.appRulesAppSection,
                  items: [
                    ListItem(
                      leading: const GlyphIcon(AppGlyphs.arrowBack, size: 20),
                      title: Text(context.l10n.appRulesBackToList),
                      subtitle: Text(app.packageName),
                      onTap: () => setState(() => _selected = null),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ..._allowDomainSlivers(draft, app, domains),
          ..._scopedRuleSlivers(app),
          SliverToBoxAdapter(child: _detailFooter(app, rules)),
        ],
      ),
    );
  }

  Future<void> _clearAll(AppRulesDraft draft) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.appRulesClearAllTitle,
        destructive: true,
        child: Text(context.l10n.appRulesClearAllBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.uiCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonClearAll),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(draft.clearAll);
  }

  /// Drops one locally edited allowlisted domain; the change lands on save.
  void _removeDomain(AppRulesDraft draft, String packageName, String domain) =>
      setState(() => draft.removeDomain(packageName, domain));

  Future<void> _addDomain(AppRulesDraft draft, String packageName) async {
    final domain = await showAppAllowDomainDialog(context);
    if (domain == null || !mounted) {
      return;
    }
    setState(() => draft.addDomain(packageName, domain));
  }

  Future<void> _addScopedRule(InstalledApp app) async {
    final result = await showAppScopedRuleDialog(context, app.packageName);
    if (result == null || !mounted) {
      return;
    }
    final controller = ref.read(appScopedRulesControllerProvider);
    final ok = await controller.addRule(
      app.packageName,
      result.kind,
      result.pattern,
    );
    if (!mounted) {
      return;
    }
    if (!ok) {
      _tip(context.l10n.appRulesRuleExists);
      return;
    }
    _tip(context.l10n.appRulesRuleAdded(result.kind.title(context.l10n)));
  }

  Future<void> _toggleScopedRule(
    InstalledApp app,
    MockRule rule,
    bool enabled,
  ) async {
    await ref
        .read(appScopedRulesControllerProvider)
        .toggle(app.packageName, rule, enabled);
  }

  Future<void> _deleteScopedRule(InstalledApp app, MockRule rule) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.appRulesDeleteRuleTitle,
        destructive: true,
        child: Text(rule.pattern),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.uiCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await ref
        .read(appScopedRulesControllerProvider)
        .delete(app.packageName, rule);
  }

  Future<void> _toggleFullBlock(InstalledApp app, bool enabled) async {
    final next = await ref
        .read(appScopedRulesControllerProvider)
        .setFullBlock(app.packageName, enabled);
    if (!mounted) {
      return;
    }
    _tip(next ? context.l10n.appRulesFullBlockOn : context.l10n.appRulesFullBlockOff);
  }

  void _tip(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}
