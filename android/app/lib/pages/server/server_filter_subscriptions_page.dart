import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ServerFilterSubscriptionsPage extends ConsumerStatefulWidget {
  const ServerFilterSubscriptionsPage({super.key});

  @override
  ConsumerState<ServerFilterSubscriptionsPage> createState() =>
      _ServerFilterSubscriptionsPageState();
}

class _ServerFilterSubscriptionsPageState
    extends ConsumerState<ServerFilterSubscriptionsPage> {
  bool _refreshing = false;

  Future<void> _save(ServerConfig config, ServerFilterConfig filter) async {
    try {
      await ref
          .read(serverControllerProvider.notifier)
          .saveConfig(config.copyWith(filter: filter));
      if (mounted) showAppSnack(context, context.l10n.serverFilterSaved);
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    }
  }

  Future<void> _add(ServerConfig config, ServerFilterConfig filter) async {
    final draft = await showFloatingDialog<ServerFilterList>(
      context: context,
      child: const _SubscriptionDialog(),
    );
    if (draft == null || !mounted) return;
    await _save(config, filter.copyWith(lists: [...filter.lists, draft]));
  }

  Future<void> _delete(
    ServerConfig config,
    ServerFilterConfig filter,
    ServerFilterList target,
  ) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.serverSubscriptionDelete,
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
    await _save(
      config,
      filter.copyWith(
        lists: [
          for (final list in filter.lists)
            if (list.id != target.id) list,
        ],
      ),
    );
  }

  Future<void> _toggle(
    ServerConfig config,
    ServerFilterConfig filter,
    ServerFilterList target,
    bool enabled,
  ) {
    return _save(
      config,
      filter.copyWith(
        lists: [
          for (final item in filter.lists)
            if (item.id == target.id)
              ServerFilterList(
                id: item.id,
                name: item.name,
                url: item.url,
                enabled: enabled,
                rulesCount: item.rulesCount,
                lastUpdated: item.lastUpdated,
                lastStatus: item.lastStatus,
                lastError: item.lastError,
              )
            else
              item,
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await ref.read(serverControllerProvider.notifier).refreshFilter();
      if (mounted) {
        showAppSnack(context, context.l10n.serverSubscriptionRefreshed);
      }
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  String _subtitle(ServerFilterList list) {
    final uri = Uri.tryParse(list.url);
    final host = uri?.host.isNotEmpty == true ? uri!.host : list.url;
    final rules = context.l10n.serverSubscriptionRules(list.rulesCount);
    return '$host · $rules';
  }

  String _status(ServerFilterList list) {
    if (list.lastError.isNotEmpty) {
      return context.l10n.serverSubscriptionError;
    }
    return list.enabled
        ? context.l10n.commonEnabled
        : context.l10n.commonDisabled;
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
    return CommonScaffold(
      title: context.l10n.serverSubscriptions,
      primaryAction: IconButtonData(
        glyph: TablerIcons.plus,
        tooltip: context.l10n.serverSubscriptionAdd,
        onPressed: () => _add(config, filter),
      ),
      iconActions: [
        IconButtonData(
          glyph: TablerIcons.refresh,
          tooltip: context.l10n.serverSubscriptionRefresh,
          onPressed: _refreshing ? null : _refresh,
        ),
      ],
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.serverSubscriptionList,
            items: [
              if (filter.lists.isEmpty)
                ListItem(
                  leading: const Icon(TablerIcons.info_circle, size: 20),
                  title: Text(context.l10n.serverSubscriptionEmpty),
                ),
              for (final list in filter.lists)
                ListItem(
                  leading: Icon(
                    list.enabled ? TablerIcons.circle_check : TablerIcons.x,
                    size: 20,
                  ),
                  title: Row(
                    spacing: 6,
                    children: [
                      Expanded(
                        child: Text(
                          list.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TonalChip(
                        label: _status(list),
                        color: list.lastError.isNotEmpty
                            ? context.colorScheme.errorContainer
                            : context.raisedSurfaceLevel.colorOf(
                                context.colorScheme,
                              ),
                        foregroundColor: list.lastError.isNotEmpty
                            ? context.colorScheme.onErrorContainer
                            : context.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  subtitle: Text(
                    _subtitle(list),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: list.enabled,
                        onChanged: (value) =>
                            _toggle(config, filter, list, value),
                      ),
                      IconButton(
                        tooltip: context.l10n.serverSubscriptionDelete,
                        onPressed: () => _delete(config, filter, list),
                        icon: const Icon(TablerIcons.trash, size: 18),
                      ),
                    ],
                  ),
                  onTap: () => _toggle(config, filter, list, !list.enabled),
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

class _SubscriptionDialog extends StatefulWidget {
  const _SubscriptionDialog();

  @override
  State<_SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<_SubscriptionDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final url = _url.text.trim();
    if (name.isEmpty || url.isEmpty) {
      setState(() => _error = context.l10n.serverSubscriptionRequired);
      return;
    }
    Navigator.of(context).pop(
      ServerFilterList(
        id: 'list-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        url: url,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: context.l10n.serverSubscriptionAddTitle,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.uiCancel),
        ),
        TextButton(onPressed: _submit, child: Text(context.l10n.commonSave)),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 14,
        children: [
          LabeledInputField(
            label: context.l10n.serverSubscriptionName,
            controller: _name,
            autofocus: true,
          ),
          LabeledInputField(
            label: context.l10n.serverSubscriptionUrl,
            controller: _url,
            hintText: 'https://example.com/rules.txt',
            autocorrect: false,
            helperText: _error,
          ),
        ],
      ),
    );
  }
}
