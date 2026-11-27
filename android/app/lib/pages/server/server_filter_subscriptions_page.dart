import 'dart:async';

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/pages/server/server_subscription_common.dart';
import 'package:diting_android/routes/server_routes.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/chip_row.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

part 'server_subscription_widgets.dart';

class ServerFilterSubscriptionsPage extends ConsumerStatefulWidget {
  const ServerFilterSubscriptionsPage({super.key});

  @override
  ConsumerState<ServerFilterSubscriptionsPage> createState() =>
      _ServerFilterSubscriptionsPageState();
}

class _ServerFilterSubscriptionsPageState
    extends ConsumerState<ServerFilterSubscriptionsPage>
    with PageVisibilityMixin<ServerFilterSubscriptionsPage> {
  String? _group;
  bool _refreshing = false;
  final _updating = <String>{};
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(serverControllerProvider.notifier).refreshConfig();
    });
  }

  @override
  void onPageVisibilityChanged(bool visible) {
    _poll?.cancel();
    _poll = visible
        ? Timer.periodic(const Duration(seconds: 10), (_) {
            if (ref.read(serverControllerProvider).value?.status.running ==
                true) {
              ref.read(serverControllerProvider.notifier).refreshConfig();
            }
          })
        : null;
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  ServerController get _controller =>
      ref.read(serverControllerProvider.notifier);

  Future<bool> _persist(
    ServerConfig config,
    List<ServerFilterList> lists,
  ) async {
    try {
      await _controller.saveConfig(
        config.copyWith(filter: config.filter.copyWith(lists: lists)),
      );
      return true;
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
      return false;
    }
  }

  Future<void> _refreshOne(String id) async {
    setState(() => _updating.add(id));
    try {
      await _controller.refreshFilter(id);
      if (mounted) {
        showAppSnack(context, context.l10n.serverSubscriptionRefreshed);
      }
    } catch (error) {
      await _controller.refreshConfig();
      if (mounted) showAppSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _updating.remove(id));
    }
  }

  Future<void> _refreshAll() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await _controller.refreshFilter();
      if (mounted) {
        showAppSnack(context, context.l10n.serverSubscriptionRefreshed);
      }
    } catch (error) {
      await _controller.refreshConfig();
      if (mounted) showAppSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _rename(ServerConfig config, ServerFilterList target) async {
    final name = await showFloatingDialog<String>(
      context: context,
      child: InputDialog(
        title: context.l10n.subsRenameTitle,
        value: target.name,
        validator: (value) =>
            (value ?? '').trim().isEmpty ? context.l10n.subsNameRequired : null,
      ),
    );
    if (name == null || !mounted) return;
    await _persist(config, [
      for (final list in config.filter.lists)
        if (list.id == target.id) list.copyWith(name: name.trim()) else list,
    ]);
  }

  Future<void> _delete(ServerConfig config, ServerFilterList target) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.serverSubscriptionDelete,
        destructive: true,
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
        child: Text(context.l10n.serverSubscriptionDeleteBody(target.name)),
      ),
    );
    if (confirmed != true || !mounted) return;
    await removeServerLocalRuleFile(target.url);
    await _persist(config, [
      for (final list in config.filter.lists)
        if (list.id != target.id) list,
    ]);
  }

  Future<void> _toggle(
    ServerConfig config,
    ServerFilterList target,
    bool value,
  ) {
    return _persist(config, [
      for (final list in config.filter.lists)
        if (list.id == target.id) list.copyWith(enabled: value) else list,
    ]);
  }

  Future<void> _editAutoUpdate(
    ServerConfig config, {
    bool? enabled,
    int? hours,
  }) async {
    try {
      await _controller.saveConfig(
        config.copyWith(
          filter: config.filter.copyWith(
            autoUpdate: enabled ?? config.filter.autoUpdate,
            updateIntervalHours: hours ?? config.filter.updateIntervalHours,
          ),
        ),
      );
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    }
  }

  Future<void> _manageGroups() async {
    await showSheet<void>(
      context: context,
      builder: (_) =>
          _ServerGroupSheet(onRename: _renameGroup, onDelete: _deleteGroup),
    );
  }

  Future<bool> _renameGroup(String from, String to) async {
    final config = ref.read(serverControllerProvider).value?.config;
    if (config == null) return false;
    final name = to.trim();
    if (name.isEmpty) return false;
    if (name != from && _groupsOf(config).contains(name)) return false;
    await _persist(config, [
      for (final list in config.filter.lists)
        if (list.group == from) list.copyWith(group: name) else list,
    ]);
    return true;
  }

  Future<void> _deleteGroup(String group) async {
    final config = ref.read(serverControllerProvider).value?.config;
    if (config == null) return;
    await _persist(config, [
      for (final list in config.filter.lists)
        if (list.group == group) list.copyWith(group: '') else list,
    ]);
    if (mounted && _group == group) {
      setState(() => _group = null);
    }
  }

  static List<String> _groupsOf(ServerConfig config) {
    final seen = <String>{};
    for (final list in config.filter.lists) {
      if (list.group.isNotEmpty) seen.add(list.group);
    }
    final groups = seen.toList()..sort();
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(serverControllerProvider).value;
    if (snapshot == null) {
      return CommonScaffold(
        title: context.l10n.serverSubscriptions,
        body: const Center(child: CommonCircleLoading()),
      );
    }
    final config = snapshot.config;
    final filter = config.filter;
    final groups = _groupsOf(config);
    final selected = _group == null
        ? filter.lists
        : [
            for (final list in filter.lists)
              if (list.group == _group) list,
          ];
    final totalRules = filter.lists.fold<int>(
      0,
      (sum, list) => sum + list.rulesCount,
    );
    final failed = filter.lists.where((list) => list.hasError).length;
    return CommonScaffold(
      title: context.l10n.serverSubscriptions,
      isLoading: _refreshing,
      primaryAction: IconButtonData(
        glyph: TablerIcons.plus,
        tooltip: context.l10n.serverSubscriptionAdd,
        onPressed: () => context.push(ServerRoutes.filterSubscriptionAdd),
      ),
      iconActions: [
        IconButtonData(
          glyph: TablerIcons.file_import,
          tooltip: context.l10n.subsMethodOtherMode,
          onPressed: () => context.push(ServerRoutes.filterSubscriptionImport),
        ),
        IconButtonData(
          glyph: TablerIcons.refresh,
          tooltip: context.l10n.subsUpdateAll,
          isLoading: _refreshing,
          onPressed: _refreshing ? null : _refreshAll,
        ),
      ],
      body: PageBody(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: CommonCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: StatStrip(
                stats: [
                  StatItem(
                    label: context.l10n.subsCount,
                    value: '${filter.lists.length}',
                  ),
                  StatItem(
                    label: context.l10n.commonEnabled,
                    value: '${filter.lists.where((l) => l.enabled).length}',
                    color: context.colorScheme.success,
                  ),
                  StatItem(
                    label: context.l10n.subsRuleCount,
                    value: serverRuleCountLabel(totalRules),
                  ),
                  if (failed > 0)
                    StatItem(
                      label: context.l10n.subsAbnormal,
                      value: '$failed',
                      color: context.colorScheme.destructive,
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: ChipRow(
                    children: [
                      FilterPill(
                        label: context.l10n.subsAllGroups,
                        selected: _group == null,
                        onPressed: () => setState(() => _group = null),
                      ),
                      for (final group in groups)
                        FilterPill(
                          label: group,
                          selected: _group == group,
                          onPressed: () => setState(() => _group = group),
                        ),
                    ],
                  ),
                ),
                if (groups.isNotEmpty)
                  TextButton.icon(
                    onPressed: _manageGroups,
                    icon: const Icon(TablerIcons.pencil, size: 16),
                    label: Text(context.l10n.subsManageGroupsShort),
                  ),
              ],
            ),
          ),
          if (filter.lists.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: CommonCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  spacing: 10,
                  children: [
                    const Icon(TablerIcons.cloud_network, size: 28),
                    Text(
                      context.l10n.subsEmptyLabel,
                      style: AppTextRole.rowTitle.of(context),
                    ),
                    Text(
                      context.l10n.subsEmptyDescription,
                      textAlign: TextAlign.center,
                      style: AppTextRole.supportingText.of(context),
                    ),
                    TonalButton(
                      label: context.l10n.serverSubscriptionAdd,
                      glyph: TablerIcons.plus,
                      onPressed: () =>
                          context.push(ServerRoutes.filterSubscriptionAdd),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final list in selected)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _ServerSubscriptionCard(
                  list: list,
                  updating:
                      _updating.contains(list.id) ||
                      (_refreshing && list.enabled),
                  busy: _refreshing || _updating.isNotEmpty,
                  onToggle: (value) => _toggle(config, list, value),
                  onUpdate: () => _refreshOne(list.id),
                  onRename: () => _rename(config, list),
                  onDelete: () => _delete(config, list),
                  onEdit: () => context.push(
                    Uri(
                      path: ServerRoutes.filterSubscriptionEdit,
                      queryParameters: {'id': list.id},
                    ).toString(),
                  ),
                ),
              ),
          generateSection(
            title: context.l10n.autoUpdateTitle,
            items: [
              ListItem.toggle(
                leading: const Icon(TablerIcons.rotate_clockwise, size: 20),
                title: Text(context.l10n.autoUpdateRulesSwitch),
                subtitle: Text(context.l10n.serverSubsAutoUpdateBody),
                value: filter.autoUpdate,
                onChanged: (value) => _editAutoUpdate(config, enabled: value),
              ),
              if (filter.autoUpdate)
                ListItem(
                  leading: const Icon(TablerIcons.clock, size: 20),
                  title: Text(context.l10n.autoUpdateIntervalSection),
                  subtitle: Text(
                    context.l10n.autoUpdateEveryHours(
                      filter.updateIntervalHours,
                    ),
                  ),
                  trailing: const Icon(TablerIcons.chevron_right, size: 18),
                  onTap: () async {
                    final value = await editServerNumber(
                      context,
                      title: context.l10n.autoUpdateIntervalSection,
                      initial: filter.updateIntervalHours,
                      min: 1,
                      max: 168,
                    );
                    if (value != null) {
                      await _editAutoUpdate(config, hours: value);
                    }
                  },
                ),
            ],
            footer: context.l10n.serverSubscriptionNote,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
