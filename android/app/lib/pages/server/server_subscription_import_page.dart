library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/db/datasets.dart';
import 'package:diting_android/data/native/platform_bridge.dart';
import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/subscriptions/subscription_url.dart';
import 'package:diting_android/pages/server/server_subscription_common.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/empty_state.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ServerSubscriptionImportPage extends ConsumerStatefulWidget {
  const ServerSubscriptionImportPage({super.key});

  @override
  ConsumerState<ServerSubscriptionImportPage> createState() =>
      _ServerSubscriptionImportPageState();
}

class _ServerSubscriptionImportPageState
    extends ConsumerState<ServerSubscriptionImportPage> {
  var _source = DataSet.normal;
  final _selected = <String>{};
  var _importing = false;

  ServerConfig? get _config => ref.read(serverControllerProvider).value?.config;

  Set<String> get _existingKeys {
    final config = _config;
    if (config == null) return const {};
    return {
      for (final list in config.filter.lists)
        '${list.kind}|${list.isRemote ? list.url : list.name}',
    };
  }

  static String _keyOf(ServerImportEntry entry) =>
      '${entry.record.kind.storageValue}|'
      '${entry.record.isRemote ? entry.record.url : entry.record.name}';

  Future<void> _import(List<ServerImportEntry> entries) async {
    final targets = [
      for (final entry in entries)
        if (_selected.contains(_keyOf(entry))) entry,
    ];
    if (targets.isEmpty) {
      showAppSnack(context, context.l10n.subsOtherModeNoneSelected);
      return;
    }
    final config = _config;
    if (config == null) return;
    setState(() => _importing = true);
    final created = <ServerFilterList>[];
    var failed = 0;
    try {
      for (final entry in targets) {
        final record = entry.record;
        final id =
            'list-${DateTime.now().microsecondsSinceEpoch}-'
            '${created.length}';
        var url = record.url;
        if (!record.isRemote) {
          final read = await PlatformBridge().readPersistedText(record.url);
          if (!read.isOk || read.text == null) {
            failed++;
            continue;
          }
          url = await copyServerLocalRuleFile(id: id, text: read.text!);
        }
        String? mirrorUrl;
        if (record.isRemote && record.mirrorTemplate != null) {
          try {
            mirrorUrl = buildMirrorUrl(record.mirrorTemplate!, url);
          } on FormatException {
            mirrorUrl = null;
          }
        }
        created.add(
          ServerFilterList(
            id: id,
            name: record.name,
            url: url,
            enabled: record.enabled,
            kind: record.kind.storageValue,
            group: entry.group,
            sourceType: record.isRemote ? 'remote' : 'local',
            mirrorTemplate: record.mirrorTemplate ?? '',
            mirrorUrl: mirrorUrl ?? '',
            mirrorFallback: record.mirrorFallback,
          ),
        );
      }
      if (created.isNotEmpty) {
        await ref
            .read(serverControllerProvider.notifier)
            .saveConfig(
              config.copyWith(
                filter: config.filter.copyWith(
                  lists: [...config.filter.lists, ...created],
                ),
              ),
            );
        for (final list in created) {
          try {
            await ref
                .read(serverControllerProvider.notifier)
                .refreshFilter(list.id);
          } catch (_) {
            await ref.read(serverControllerProvider.notifier).refreshConfig();
          }
        }
      }
      if (!mounted) return;
      showAppSnack(
        context,
        failed == 0
            ? context.l10n.serverSubsImported(created.length)
            : context.l10n.serverSubsImportedPartial(created.length, failed),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _importing = false);
        showAppSnack(context, error.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncEntries = ref.watch(
      serverOtherModeSubscriptionsProvider(_source),
    );
    final entries = asyncEntries.value ?? const <ServerImportEntry>[];
    final existing = _existingKeys;
    final importable = [
      for (final entry in entries)
        if (!existing.contains(_keyOf(entry))) entry,
    ];
    return CommonScaffold(
      title: context.l10n.serverSubsImportTitle,
      isLoading: _importing,
      confirmationAction: IconButtonData(
        glyph: TablerIcons.check,
        tooltip: context.l10n.serverSubsImportAction,
        onPressed: _importing ? null : () => _import(entries),
      ),
      body: PageBody(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedControl<DataSet>(
              segments: [
                (
                  DataSet.normal,
                  serverDataSourceLabel(DataSet.normal, context.l10n),
                ),
                (
                  DataSet.express,
                  serverDataSourceLabel(DataSet.express, context.l10n),
                ),
              ],
              value: _source,
              onChanged: (value) => setState(() {
                _source = value;
                _selected.clear();
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              context.l10n.subsOtherModeExplain(
                serverDataSourceLabel(_source, context.l10n),
              ),
              style: AppTextRole.supportingText.of(context),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.subsOtherModeSelected(_selected.length),
                    style: AppTextRole.supportingText.of(context),
                  ),
                ),
                TextButton(
                  onPressed: importable.isEmpty
                      ? null
                      : () => setState(() {
                          if (_selected.length == importable.length) {
                            _selected.clear();
                          } else {
                            _selected.addAll(importable.map(_keyOf));
                          }
                        }),
                  child: Text(
                    _selected.length == importable.length &&
                            importable.isNotEmpty
                        ? context.l10n.subsOtherModeClearAll
                        : context.l10n.subsOtherModeSelectAll,
                  ),
                ),
              ],
            ),
          ),
          asyncEntries.when(
            data: (_) {
              if (entries.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: EmptyStateBox(
                    minHeight: 240,
                    child: NullStatus(
                      label: context.l10n.subsOtherModeEmptyTitle(
                        serverDataSourceLabel(_source, context.l10n),
                      ),
                      description: context.l10n.subsOtherModeEmptyBody(
                        serverDataSourceLabel(_source, context.l10n),
                      ),
                      illustration: NullStatusIllustration.rules,
                    ),
                  ),
                );
              }
              if (importable.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    context.l10n.subsOtherModeAllImported,
                    style: AppTextRole.supportingText.of(context),
                  ),
                );
              }
              return generateSection(
                title: context.l10n.subsOtherModeList,
                items: [
                  for (final entry in entries)
                    ListItem(
                      leading: Icon(
                        entry.record.isRemote
                            ? TablerIcons.cloud_network
                            : TablerIcons.file_import,
                        size: 20,
                      ),
                      title: Text(
                        entry.record.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          if (entry.group.isNotEmpty) entry.group,
                          entry.record.kind.displayName(context.l10n),
                          entry.record.sourceType.label(context.l10n),
                          entry.record.url,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: existing.contains(_keyOf(entry))
                          ? Text(
                              context.l10n.subsOtherModeAlready,
                              style: AppTextRole.caption.of(context),
                            )
                          : CommonCheckBox(
                              value: _selected.contains(_keyOf(entry)),
                              onChanged: (value) => setState(() {
                                if (value == true) {
                                  _selected.add(_keyOf(entry));
                                } else {
                                  _selected.remove(_keyOf(entry));
                                }
                              }),
                            ),
                      onTap: existing.contains(_keyOf(entry))
                          ? null
                          : () => setState(() {
                              final key = _keyOf(entry);
                              if (!_selected.add(key)) {
                                _selected.remove(key);
                              }
                            }),
                    ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CommonCircleLoading()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                '${context.l10n.subsOtherModeLoadFailed}: $error',
                style: AppTextRole.supportingText.of(context),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
