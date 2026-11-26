import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/routes/dns64_routes.dart';
import 'package:diting_android/state/appearance_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class ResolutionModePage extends ConsumerStatefulWidget {
  const ResolutionModePage({super.key});

  @override
  ConsumerState<ResolutionModePage> createState() => _ResolutionModePageState();
}

class _ResolutionModePageState extends ConsumerState<ResolutionModePage> {
  static String _descriptionOf(ResolutionMode mode, AppL10n l10n) =>
      switch (mode) {
        ResolutionMode.single => l10n.resolutionSingleDesc,
        ResolutionMode.smart => l10n.resolutionSmartDesc,
        ResolutionMode.parallel => l10n.resolutionParallelDesc,
        ResolutionMode.primaryBackup => l10n.resolutionPrimaryBackupDesc,
      };

  Future<void> _selectPresetProtocol(ProviderProtocol protocol) async {
    if (!ref.read(presetProtocolProvider.notifier).select(protocol)) return;
    final error = await ref
        .read(powerProvider.notifier)
        .applyDnsConfigIfRunning();
    if (error == null || !mounted) return;
    showAppSnack(context, context.l10n.resolutionProtocolSavedError(error));
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(resolutionModeProvider);
    final presetProtocol = ref.watch(presetProtocolProvider);
    final selectedId = ref.watch(selectedProviderProvider);
    final raceIds = ref.watch(raceProvidersProvider);
    final colorScheme = context.colorScheme;
    final catalog = ref.watch(dnsProviderCatalogProvider);
    final singleProvider = catalog
        .where((provider) => provider.id == selectedId)
        .firstOrNull;
    return CommonScaffold(
      title: context.l10n.resolutionModeTitle,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.resolutionCurrentSection,
            items: [
              ListItem<ResolutionMode>.options(
                leading: const Icon(TablerIcons.arrows_shuffle),
                title: Text(context.l10n.resolutionModeTitle),
                subtitle: Text(_descriptionOf(mode, context.l10n)),
                value: mode,
                options: ResolutionMode.values,
                textBuilder: (option) => option.label(context.l10n),
                onChanged: (option) =>
                    ref.read(resolutionModeProvider.notifier).select(option),
              ),
            ],
          ),
          const SizedBox(height: 12),
          generateSection(
            title: context.l10n.resolutionBuiltinSection,
            items: [
              ListItem<ProviderProtocol>.options(
                leading: const Icon(TablerIcons.server_2),
                title: Text(context.l10n.resolutionBuiltinProtocol),
                subtitle: Text(context.l10n.resolutionBuiltinNote),
                value: presetProtocol,
                options: ProviderProtocol.values,
                textBuilder: (protocol) => protocol.label,
                onChanged: _selectPresetProtocol,
              ),
            ],
          ),
          generateSection(
            title: context.l10n.resolutionConfigSection,
            footer: context.l10n.resolutionConfigFooter,
            items: [
              for (final option in ResolutionMode.values)
                ListItem(
                  leading: Icon(_glyphOf(option), size: 20),
                  title: Text(option.label(context.l10n)),
                  subtitle: Text(_descriptionOf(option, context.l10n)),
                  trailing: Text(
                    _summaryOf(
                      context.l10n,
                      option,
                      singleProvider,
                      raceIds.length,
                    ),
                    style: AppTextRole.supportingText
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  onTap: () => context.push('/hub/resolution/${_idOf(option)}'),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static IconData _glyphOf(ResolutionMode mode) => switch (mode) {
    ResolutionMode.single => TablerIcons.cloud_upload,
    ResolutionMode.smart => TablerIcons.sparkles,
    ResolutionMode.parallel => TablerIcons.gauge,
    ResolutionMode.primaryBackup => TablerIcons.arrows_exchange,
  };

  static String _summaryOf(
    AppL10n l10n,
    ResolutionMode mode,
    MockProvider? singleProvider,
    int raceCount,
  ) => switch (mode) {
    ResolutionMode.single =>
      singleProvider?.name ?? l10n.resolutionNotConfigured,
    _ => l10n.resolutionProviderCount(raceCount),
  };

  static String _idOf(ResolutionMode mode) => switch (mode) {
    ResolutionMode.single => 'single',
    ResolutionMode.smart => 'smart',
    ResolutionMode.parallel => 'parallel',
    ResolutionMode.primaryBackup => 'backup',
  };
}

class ResolutionModeConfigPage extends ConsumerStatefulWidget {
  const ResolutionModeConfigPage({super.key, required this.modeId});

  final String modeId;

  @override
  ConsumerState<ResolutionModeConfigPage> createState() =>
      _ResolutionModeConfigPageState();
}

class _ResolutionModeConfigPageState
    extends ConsumerState<ResolutionModeConfigPage> {
  ProviderProtocol? _protocol;

  ResolutionMode get _mode => switch (widget.modeId) {
    'smart' => ResolutionMode.smart,
    'parallel' => ResolutionMode.parallel,
    'backup' => ResolutionMode.primaryBackup,
    _ => ResolutionMode.single,
  };

  bool get _single => _mode == ResolutionMode.single;

  void _select(MockProvider provider) {
    if (_single) {
      ref.read(selectedProviderProvider.notifier).select(provider.id);
      return;
    }
    final before = ref.read(raceProvidersProvider);
    if (before.contains(provider.id) &&
        before.length <= RaceProvidersNotifier.minCount) {
      showAppSnack(context, context.l10n.resolutionMinProviders);
      return;
    }
    ref.read(raceProvidersProvider.notifier).toggle(provider.id);
  }

  void _move(List<String> visibleIds, String id, int delta) {
    final index = visibleIds.indexOf(id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= visibleIds.length) {
      return;
    }
    final other = visibleIds[target];
    final next = ref.read(raceProvidersProvider).toList();
    final from = next.indexOf(id);
    final to = next.indexOf(other);
    if (from < 0 || to < 0) {
      return;
    }
    next[from] = other;
    next[to] = id;
    ref.read(raceProvidersProvider.notifier).reorder(next);
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = ref.watch(selectedProviderProvider);
    final raceIds = ref.watch(raceProvidersProvider);
    final catalog = ref.watch(dnsProviderCatalogProvider);
    final ProviderProtocol protocol =
        _protocol ?? ref.watch(presetProtocolProvider);
    final providers = catalog
        .where((provider) => provider.protocol == protocol)
        .toList(growable: false);
    final selectedCount = _single ? 1 : raceIds.length;
    final valid = _single
        ? providers.any((provider) => provider.id == selectedId)
        : selectedCount >= RaceProvidersNotifier.minCount;
    final ordered = [
      for (final id in raceIds)
        ...catalog.where(
          (provider) => provider.id == id && provider.protocol == protocol,
        ),
    ];
    final rest = [
      for (final provider in providers)
        if (!raceIds.contains(provider.id)) provider,
    ];
    final orderedIds = [for (final provider in ordered) provider.id];
    return CommonScaffold(
      title: _mode.label(context.l10n),
      body: PageBody(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: CommonCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                spacing: 12,
                children: [
                  Icon(
                    _single ? TablerIcons.cloud_upload : TablerIcons.gauge,
                    size: 22,
                    color: context.colorScheme.primary,
                  ),
                  Expanded(
                    child: Text(
                      _single
                          ? context.l10n.resolutionSingleHint
                          : context.l10n.resolutionRaceHint(selectedCount),
                      style: AppTextRole.supportingText.of(context),
                    ),
                  ),
                  TonalChip(
                    label: valid
                        ? context.l10n.resolutionReady
                        : context.l10n.resolutionPending,
                    color: valid
                        ? context.colorScheme.primary
                        : context.raisedSurfaceLevel.colorOf(
                            context.colorScheme,
                          ),
                    foregroundColor: valid
                        ? context.colorScheme.onPrimary
                        : context.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          generateSection(
            title: context.l10n.resolutionBuiltinSection,
            items: [
              ListItem<ProviderProtocol>.options(
                leading: const Icon(TablerIcons.server_2),
                title: Text(context.l10n.resolutionBuiltinProtocol),
                value: protocol,
                options: ProviderProtocol.values,
                textBuilder: (option) => option.label,
                onChanged: (value) => setState(() => _protocol = value),
              ),
            ],
          ),
          generateSection(
            title: switch (_mode) {
              ResolutionMode.single => context.l10n.resolutionSectionSingle,
              ResolutionMode.smart => context.l10n.resolutionSectionSmart,
              ResolutionMode.parallel => context.l10n.resolutionSectionParallel,
              ResolutionMode.primaryBackup =>
                context.l10n.resolutionSectionBackup,
            },
            items: [
              if (providers.isEmpty)
                ListItem(
                  leading: const Icon(TablerIcons.info_circle),
                  title: Text(context.l10n.resolutionNoProviders),
                ),
              for (final provider in [...ordered, ...rest])
                ListItem(
                  leading: Icon(
                    (_single
                            ? provider.id == selectedId
                            : raceIds.contains(provider.id))
                        ? TablerIcons.circle_check
                        : TablerIcons.cloud_upload,
                    size: 20,
                  ),
                  title: Text(provider.name),
                  subtitle: Text(provider.address),
                  trailing:
                      _mode == ResolutionMode.primaryBackup &&
                          raceIds.contains(provider.id)
                      ? _OrderButtons(
                          onUp: () => _move(orderedIds, provider.id, -1),
                          onDown: () => _move(orderedIds, provider.id, 1),
                        )
                      : null,
                  onTap: () => _select(provider),
                ),
            ],
          ),
          generateSection(
            title: context.l10n.hubModuleMore,
            items: [
              ListItem(
                leading: const Icon(TablerIcons.link),
                title: Text(context.l10n.dns64Title),
                subtitle: Text(context.l10n.dns64Intro),
                onTap: () => context.push(Dns64Paths.root),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _OrderButtons extends StatelessWidget {
  const _OrderButtons({required this.onUp, required this.onDown});

  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: context.l10n.resolutionMoveUp,
          onPressed: onUp,
          icon: const Icon(TablerIcons.arrow_up, size: 18),
        ),
        IconButton(
          tooltip: context.l10n.resolutionMoveDown,
          onPressed: onDown,
          icon: const Icon(TablerIcons.arrow_down, size: 18),
        ),
      ],
    );
  }
}
