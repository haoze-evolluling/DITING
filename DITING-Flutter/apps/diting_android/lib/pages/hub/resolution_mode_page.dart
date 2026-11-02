import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_shared/state/appearance_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Resolution mode home (upstream `ResolutionModeHomeScreen`): current mode, built-in
/// protocol and four mode cards, all driven by the existing `ResolutionMode` state.
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
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(context.l10n.resolutionProtocolSavedError(error)),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: CommonCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                spacing: 12,
                children: [
                  GlyphIcon(
                    AppGlyphs.shuffle,
                    size: 24,
                    color: colorScheme.primary,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(mode.label(context.l10n), style: context.listTitleStyle),
                        Text(
                          _descriptionOf(mode, context.l10n),
                          style: context.listSubtitleStyle,
                        ),
                      ],
                    ),
                  ),
                  const GlyphIcon(AppGlyphs.chevronForward, size: 18),
                ],
              ),
              onPressed: () => _showModePicker(context, mode),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 6,
              children: [
                Text(context.l10n.resolutionBuiltinProtocol, style: context.listTitleStyle),
                SegmentedControl<ProviderProtocol>(
                  segments: [
                    for (final protocol in ProviderProtocol.values)
                      (protocol, protocol.label),
                  ],
                  value: presetProtocol,
                  onChanged: _selectPresetProtocol,
                ),
                Text(
                  context.l10n.resolutionBuiltinNote,
                  style: context.listSubtitleStyle,
                ),
              ],
            ),
          ),
          generateSection(
            title: context.l10n.resolutionConfigSection,
            footer: context.l10n.resolutionConfigFooter,
            items: [
              for (final option in ResolutionMode.values)
                ListItem(
                  leading: GlyphIcon(_glyphOf(option), size: 20),
                  title: Text(option.label(context.l10n)),
                  subtitle: Text(_descriptionOf(option, context.l10n)),
                  trailing: Text(
                    _summaryOf(context.l10n, option, singleProvider, raceIds.length),
                    style: AppTextStyle.footnote
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

  static Glyph _glyphOf(ResolutionMode mode) => switch (mode) {
    ResolutionMode.single => AppGlyphs.dns,
    ResolutionMode.smart => AppGlyphs.sparkle,
    ResolutionMode.parallel => AppGlyphs.speed,
    ResolutionMode.primaryBackup => AppGlyphs.swap,
  };

  static String _summaryOf(
    AppL10n l10n,
    ResolutionMode mode,
    MockProvider? singleProvider,
    int raceCount,
  ) => switch (mode) {
    ResolutionMode.single => singleProvider?.name ?? l10n.resolutionNotConfigured,
    _ => l10n.resolutionProviderCount(raceCount),
  };

  static String _idOf(ResolutionMode mode) => switch (mode) {
    ResolutionMode.single => 'single',
    ResolutionMode.smart => 'smart',
    ResolutionMode.parallel => 'parallel',
    ResolutionMode.primaryBackup => 'backup',
  };

  void _showModePicker(BuildContext context, ResolutionMode current) {
    showFloatingDialog<void>(
      context: context,
      child: CommonDialog(
        title: context.l10n.resolutionPickerTitle,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ResolutionMode.values)
              ListItem(
                leading: GlyphIcon(_glyphOf(mode), size: 20),
                title: Text(mode.label(context.l10n)),
                subtitle: Text(_descriptionOf(mode, context.l10n)),
                trailing: mode == current ? const SelectionCheck() : null,
                onTap: () {
                  ref.read(resolutionModeProvider.notifier).select(mode);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
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
  /// Local filter; null follows the built-in protocol until the user picks one here.
  ProviderProtocol? _protocol;
  late List<String> _order;

  ResolutionMode get _mode => switch (widget.modeId) {
    'smart' => ResolutionMode.smart,
    'parallel' => ResolutionMode.parallel,
    'backup' => ResolutionMode.primaryBackup,
    _ => ResolutionMode.single,
  };

  bool get _single => _mode == ResolutionMode.single;

  @override
  void initState() {
    super.initState();
    final race = ref.read(raceProvidersProvider);
    final catalog = ref.read(dnsProviderCatalogProvider);
    _order = [
      for (final provider in catalog)
        if (race.contains(provider.id)) provider.id,
    ];
  }

  void _select(MockProvider provider) {
    if (_single) {
      ref.read(selectedProviderProvider.notifier).select(provider.id);
      return;
    }
    final notifier = ref.read(raceProvidersProvider.notifier);
    final before = ref.read(raceProvidersProvider);
    final willRemove = before.contains(provider.id);
    if (willRemove && before.length <= RaceProvidersNotifier.minCount) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.l10n.resolutionMinProviders),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    notifier.toggle(provider.id);
    final next = ref.read(raceProvidersProvider);
    setState(() {
      final nextOrder = [..._order];
      if (next.contains(provider.id) && !nextOrder.contains(provider.id)) {
        nextOrder.add(provider.id);
      }
      nextOrder.removeWhere((id) => !next.contains(id));
      _order = nextOrder;
    });
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _order.length) {
      return;
    }
    setState(() {
      final item = _order.removeAt(index);
      _order.insert(target, item);
    });
    // Primary-to-backup order is persisted (the engine tries providers in list order).
    ref.read(raceProvidersProvider.notifier).reorder(_order);
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
      for (final id in _order)
        ...catalog.where(
          (provider) => provider.id == id && provider.protocol == protocol,
        ),
    ];
    final rest = [
      for (final provider in providers)
        if (!_order.contains(provider.id)) provider,
    ];
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
                  GlyphIcon(
                    _single ? AppGlyphs.dns : AppGlyphs.speed,
                    size: 22,
                    color: context.colorScheme.primary,
                  ),
                  Expanded(
                    child: Text(
                      _mode == ResolutionMode.single
                          ? context.l10n.resolutionSingleHint
                          : context.l10n.resolutionRaceHint(selectedCount),
                      style: context.listSubtitleStyle,
                    ),
                  ),
                  TonalChip(
                    label: valid ? context.l10n.resolutionReady : context.l10n.resolutionPending,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedControl<ProviderProtocol>(
              segments: [
                for (final option in ProviderProtocol.values)
                  (option, option.label),
              ],
              value: protocol,
              onChanged: (value) => setState(() => _protocol = value),
            ),
          ),
          generateSection(
            title: switch (_mode) {
              ResolutionMode.single => context.l10n.resolutionSectionSingle,
              ResolutionMode.smart => context.l10n.resolutionSectionSmart,
              ResolutionMode.parallel => context.l10n.resolutionSectionParallel,
              ResolutionMode.primaryBackup => context.l10n.resolutionSectionBackup,
            },
            items: [
              for (final provider in [...ordered, ...rest])
                ListItem(
                  leading: GlyphIcon(
                    _single
                        ? (provider.id == selectedId
                              ? AppGlyphs.checkCircle
                              : AppGlyphs.dns)
                        : (raceIds.contains(provider.id)
                              ? AppGlyphs.checkCircle
                              : AppGlyphs.dns),
                    size: 20,
                  ),
                  title: Text(provider.name),
                  subtitle: Text(provider.address),
                  trailing:
                      _mode == ResolutionMode.primaryBackup &&
                          raceIds.contains(provider.id)
                      ? _OrderButtons(
                          onUp: () => _move(_order.indexOf(provider.id), -1),
                          onDown: () => _move(_order.indexOf(provider.id), 1),
                        )
                      : null,
                  onTap: () => _select(provider),
                ),
            ],
            footer: providers.isEmpty ? context.l10n.resolutionNoProviders : null,
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
          icon: const GlyphIcon(AppGlyphs.arrowUp, size: 18),
        ),
        IconButton(
          tooltip: context.l10n.resolutionMoveDown,
          onPressed: onDown,
          icon: const GlyphIcon(AppGlyphs.arrowDown, size: 18),
        ),
      ],
    );
  }
}
