import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ServerFilterPage extends ConsumerStatefulWidget {
  const ServerFilterPage({super.key});

  @override
  ConsumerState<ServerFilterPage> createState() => _ServerFilterPageState();
}

class _ServerFilterPageState extends ConsumerState<ServerFilterPage> {
  final _rules = TextEditingController();
  final _checkDomain = TextEditingController();
  bool _rulesReady = false;
  bool _refreshing = false;
  ServerFilterCheck? _checkResult;

  @override
  void dispose() {
    _rules.dispose();
    _checkDomain.dispose();
    super.dispose();
  }

  void _fillRules(ServerFilterConfig filter) {
    if (_rulesReady) return;
    _rules.text = filter.customRules.join('\n');
    _rulesReady = true;
  }

  Future<void> _save(
    ServerConfig config,
    ServerFilterConfig filter, {
    bool notify = true,
  }) async {
    try {
      await ref.read(serverControllerProvider.notifier).saveConfig(
        config.copyWith(filter: filter),
      );
      if (notify && mounted) {
        showAppSnack(context, context.l10n.serverFilterSaved);
      }
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    }
  }

  Future<void> _saveRules(ServerConfig config, ServerFilterConfig filter) {
    final rules = _rules.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    return _save(config, filter.copyWith(customRules: rules));
  }

  Future<void> _refresh(ServerConfig config) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final filter = await ref
          .read(serverControllerProvider.notifier)
          .refreshFilter();
      if (mounted) {
        _rules.text = filter.customRules.join('\n');
        showAppSnack(context, context.l10n.serverSubscriptionRefreshed);
      }
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _check() async {
    final domain = _checkDomain.text.trim();
    if (domain.isEmpty) {
      showAppSnack(context, context.l10n.serverCheckDomainRequired);
      return;
    }
    try {
      final result = await ref
          .read(serverClientProvider)
          .filterCheck(domain);
      if (mounted) setState(() => _checkResult = result);
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    }
  }

  Future<void> _addSubscription(
    ServerConfig config,
    ServerFilterConfig filter,
  ) async {
    final draft = await showFloatingDialog<ServerFilterList>(
      context: context,
      child: const _SubscriptionDialog(),
    );
    if (draft == null || !mounted) return;
    await _save(
      config,
      filter.copyWith(lists: [...filter.lists, draft]),
    );
  }

  Future<void> _deleteSubscription(
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

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(serverControllerProvider).value;
    if (snapshot == null) {
      return CommonScaffold(
        title: context.l10n.serverFilterTitle,
        body: const Center(child: CommonCircleLoading()),
      );
    }
    final config = snapshot.config;
    final filter = config.filter;
    _fillRules(filter);
    return CommonScaffold(
      title: context.l10n.serverFilterTitle,
      primaryAction: IconButtonData(
        glyph: AppGlyphs.check,
        tooltip: context.l10n.commonSave,
        onPressed: () => _saveRules(config, filter),
      ),
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.add,
          tooltip: context.l10n.serverSubscriptionAdd,
          onPressed: () => _addSubscription(config, filter),
        ),
        IconButtonData(
          glyph: AppGlyphs.refresh,
          tooltip: context.l10n.serverSubscriptionRefresh,
          onPressed: _refreshing ? null : () => _refresh(config),
        ),
      ],
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.serverFilterTitle,
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.rules, size: 20),
                title: Text(context.l10n.serverFilterEnabled),
                subtitle: Text(context.l10n.serverFilterEnabledBody),
                value: filter.enabled,
                onChanged: (value) =>
                    _save(config, filter.copyWith(enabled: value)),
              ),
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.shield, size: 20),
                title: Text(context.l10n.serverFilterResponse),
                subtitle: Text(context.l10n.serverFilterResponseBody),
                value: filter.filterResponse,
                onChanged: (value) =>
                    _save(config, filter.copyWith(filterResponse: value)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
            child: Text(
              context.l10n.serverFilterBlockMode,
              style: context.listTitleStyle,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedControl<String>(
              segments: [
                ('null_ip', context.l10n.serverBlockNullIp),
                ('nxdomain', context.l10n.serverBlockNxdomain),
                ('refused', context.l10n.serverBlockRefused),
              ],
              value: filter.blockMode,
              onChanged: (value) =>
                  _save(config, filter.copyWith(blockMode: value)),
            ),
          ),
          if (filter.blockMode == 'null_ip')
            generateSection(
              title: context.l10n.serverBlockAddresses,
              items: [
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.network, size: 20),
                  title: Text(context.l10n.serverBlockingIPv4),
                  trailing: Text(
                    filter.blockingIPv4,
                    style: context.listSubtitleStyle,
                  ),
                  onTap: () async {
                    final value = await _textValue(
                      context,
                      title: context.l10n.serverBlockingIPv4,
                      initial: filter.blockingIPv4,
                    );
                    if (value == null) return;
                    await _save(
                      config,
                      filter.copyWith(blockingIPv4: value),
                    );
                  },
                ),
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.network, size: 20),
                  title: Text(context.l10n.serverBlockingIPv6),
                  trailing: Text(
                    filter.blockingIPv6,
                    style: context.listSubtitleStyle,
                  ),
                  onTap: () async {
                    final value = await _textValue(
                      context,
                      title: context.l10n.serverBlockingIPv6,
                      initial: filter.blockingIPv6,
                    );
                    if (value == null) return;
                    await _save(
                      config,
                      filter.copyWith(blockingIPv6: value),
                    );
                  },
                ),
              ],
            ),
          generateSection(
            title: context.l10n.serverCustomRules,
            items: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _rules,
                  minLines: 6,
                  maxLines: 14,
                  autocorrect: false,
                  decoration: InputDecoration(
                    hintText: context.l10n.serverCustomRulesHint,
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
            footer: context.l10n.serverCustomRulesNote,
          ),
          generateSection(
            title: context.l10n.serverSubscriptions,
            items: [
              if (filter.lists.isEmpty)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.info, size: 20),
                  title: Text(context.l10n.serverSubscriptionEmpty),
                ),
              for (final list in filter.lists)
                ListItem(
                  leading: GlyphIcon(
                    list.enabled ? AppGlyphs.checkCircle : AppGlyphs.close,
                    size: 20,
                  ),
                  title: Text(list.name),
                  subtitle: Text(
                    '${list.url}\n${context.l10n.serverSubscriptionRules(list.rulesCount)}'
                    '${list.lastError.isEmpty ? '' : ' · ${list.lastError}'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: list.enabled,
                        onChanged: (value) => _save(
                          config,
                          filter.copyWith(
                            lists: [
                              for (final item in filter.lists)
                                if (item.id == list.id)
                                  ServerFilterList(
                                    id: item.id,
                                    name: item.name,
                                    url: item.url,
                                    enabled: value,
                                    rulesCount: item.rulesCount,
                                    lastUpdated: item.lastUpdated,
                                    lastStatus: item.lastStatus,
                                    lastError: item.lastError,
                                  )
                                else
                                  item,
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: context.l10n.serverSubscriptionDelete,
                        onPressed: () =>
                            _deleteSubscription(config, filter, list),
                        icon: const GlyphIcon(AppGlyphs.delete, size: 18),
                      ),
                    ],
                  ),
                ),
            ],
            footer: context.l10n.serverSubscriptionNote,
          ),
          _CheckSection(
            controller: _checkDomain,
            result: _checkResult,
            onCheck: _check,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _CheckSection extends StatelessWidget {
  const _CheckSection({
    required this.controller,
    required this.result,
    required this.onCheck,
  });

  final TextEditingController controller;
  final ServerFilterCheck? result;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    return generateSection(
      title: context.l10n.serverCheckTitle,
      items: [
        ListItem(
          leading: const GlyphIcon(AppGlyphs.search, size: 20),
          title: TextField(
            controller: controller,
            autocorrect: false,
            onSubmitted: (_) => onCheck(),
            decoration: InputDecoration(
              labelText: context.l10n.serverCheckDomain,
              hintText: 'ads.example.com',
              border: InputBorder.none,
            ),
          ),
          trailing: TextButton(
            onPressed: onCheck,
            child: Text(context.l10n.serverCheckAction),
          ),
        ),
        if (result != null)
          ListItem(
            leading: GlyphIcon(
              result!.blocked ? AppGlyphs.block : AppGlyphs.checkCircle,
              size: 20,
            ),
            title: Text(
              result!.blocked
                  ? context.l10n.serverCheckBlocked
                  : context.l10n.serverCheckAllowed,
            ),
            subtitle: Text(
              [
                if (result!.matchedRule.isNotEmpty) result!.matchedRule,
                if (result!.listName.isNotEmpty) result!.listName,
                if (result!.reason.isNotEmpty) result!.reason,
              ].join(' · '),
            ),
          ),
      ],
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
        spacing: 10,
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: context.l10n.serverSubscriptionName,
            ),
          ),
          TextField(
            controller: _url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: context.l10n.serverSubscriptionUrl,
              hintText: 'https://example.com/rules.txt',
              errorText: _error,
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> _textValue(
  BuildContext context, {
  required String title,
  required String initial,
}) async {
  final controller = TextEditingController(text: initial);
  final value = await showFloatingDialog<String>(
    context: context,
    child: CommonDialog(
      title: title,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.uiCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: Text(context.l10n.commonSave),
        ),
      ],
      child: TextField(controller: controller, autofocus: true),
    ),
  );
  controller.dispose();
  return value == null || value.isEmpty ? null : value;
}
