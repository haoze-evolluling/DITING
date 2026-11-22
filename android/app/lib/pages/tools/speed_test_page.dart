part of 'tools_page.dart';

class SpeedTestPage extends ConsumerStatefulWidget {
  const SpeedTestPage({super.key});

  @override
  ConsumerState<SpeedTestPage> createState() => _SpeedTestPageState();
}

class _SpeedTestPageState extends ConsumerState<SpeedTestPage> {
  final _domain = TextEditingController();

  var _domainBound = false;

  @override
  void dispose() {
    _domain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final protocols = ref.watch(latencyTestProtocolsProvider);
    final protocol = ref.watch(latencyProtocolProvider);
    final domain = ref.watch(latencyDomainProvider);
    final selected = ref.watch(latencySelectionProvider);
    final state = ref.watch(latencyTestProvider);
    final available = ref.watch(latencyTestAvailableProvider);
    final catalog = ref.watch(latencyTestCatalogProvider);
    final providers = [
      for (final spec in catalog)
        if (spec.protocol == protocol) spec,
    ];
    if (!_domainBound) {
      _domainBound = true;
      _domain.text = domain;
    }
    final unavailable = available.value == false || state.unavailable;
    final barMax = latencyBarMax(state.results);
    final showEmpty = !state.running && state.results.isEmpty && !unavailable;

    return CommonScaffold(
      title: l10n.toolSpeedTest,
      body: PageBody(
        children: [
          if (available.isLoading) _ToolNotice(text: l10n.toolSpeedChecking),
          if (unavailable)
            _ToolNotice(
              text: l10n.toolSpeedUnsupported,
              isError: true,
              glyph: TablerIcons.alert_triangle,
            ),
          _ToolInputCard(
            child: _ToolField(
              controller: _domain,
              hintText: l10n.toolSpeedDomainHint,
              glyph: TablerIcons.language,
              enabled: !state.running && !unavailable,
              onChanged: (value) =>
                  ref.read(latencyDomainProvider.notifier).setDomain(value),
              onSubmitted: (_) => _run(),
            ),
          ),
          const SizedBox(height: 12),
          generateSection(
            title: l10n.obsProtocol,
            items: [
              ListItem<DnsLatencyProtocol>.options(
                leading: const Icon(TablerIcons.gauge),
                title: Text(l10n.obsProtocol),
                value: protocol,
                options: protocols,
                textBuilder: (item) => item.label,
                onChanged: (value) {
                  if (!state.running) {
                    ref.read(latencyProtocolProvider.notifier).select(value);
                  }
                },
              ),
            ],
          ),
          generateSection(
            title: l10n.toolSpeedProviders,
            items: [
              if (providers.isEmpty)
                ListItem(
                  leading: const Icon(TablerIcons.info_circle, size: 20),
                  title: Text(l10n.toolNoProviders(protocol.label)),
                  subtitle: Text(l10n.toolNoProvidersBody),
                )
              else
                for (final spec in providers)
                  ListItem.checkbox(
                    value: selected.contains(spec.id),
                    leading: const Icon(TablerIcons.cloud_upload, size: 20),
                    title: Text(spec.name),
                    subtitle: Text(latencyEndpointLabel(spec)),
                    onChanged: state.running
                        ? null
                        : (_) => ref
                              .read(latencySelectionProvider.notifier)
                              .toggle(spec.id),
                  ),
            ],
            footer: l10n.toolSpeedSelectionNote,
          ),
          if (state.error case final error?)
            _ToolNotice(text: error, isError: true, glyph: TablerIcons.alert_circle),
          _RunButton(
            glyph: TablerIcons.gauge,
            label: l10n.toolTestQueryTime,
            runningLabel: l10n.toolSpeedRunning,
            running: state.running,
            onPressed: unavailable || selected.isEmpty ? null : _run,
          ),
          if (showEmpty)
            _ToolEmptyCard(
              glyph: TablerIcons.gauge,
              title: l10n.toolSpeedEmptyTitle,
              body: l10n.toolSpeedEmpty,
            ),
          if (state.results.isNotEmpty) ...[
            generateSection(
              title: l10n.toolSpeedResults,
              items: [
                for (final (index, sample) in state.results.indexed)
                  _SpeedResultRow(
                    sample: sample,
                    rank: index + 1,
                    isFastest: index == 0 && sample.success,
                    barMax: barMax,
                  ),
              ],
              footer: l10n.toolSpeedResultsFooter(domain),
            ),
          ],
          ListFooter(text: l10n.toolSpeedFooter),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _run() async {
    ref.read(latencyTestProvider.notifier).clearError();
    await ref.read(latencyTestProvider.notifier).run();
    if (!mounted) {
      return;
    }
    final error = ref.read(latencyTestProvider).error;
    if (error != null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

class _SpeedResultRow extends StatelessWidget {
  const _SpeedResultRow({
    required this.sample,
    required this.rank,
    required this.isFastest,
    required this.barMax,
  });

  final DnsLatencySample sample;
  final int rank;
  final bool isFastest;
  final int barMax;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final share = barMax <= 0 ? 0.0 : sample.elapsedMs / barMax;
    return ListItem(
      padding: EdgeInsets.zero,
      minVerticalPadding: 0,
      minTileHeight: 0,
      title: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            Row(
              spacing: 8,
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    '$rank',
                    style: AppTextRole.bodyStrong
                        .of(context)
                        .copyWith(
                          fontFeatures: appTabularFigures,
                          color: isFastest
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                Expanded(
                  child: Text(
                    sample.providerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextRole.rowTitle.of(context),
                  ),
                ),
                TonalChip(
                  label: sample.protocol.label,
                  color: context.raisedSurfaceLevel.colorOf(colorScheme),
                  foregroundColor: colorScheme.onSurfaceVariant,
                ),
                if (isFastest)
                  TonalChip(
                    label: context.l10n.toolFastest,
                    color: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                  ),
              ],
            ),
            if (sample.success) ...[
              Text(
                '${sample.elapsedMs} ms',
                style: AppTextRole.sectionTitle
                    .of(context)
                    .copyWith(
                      fontFeatures: appTabularFigures,
                      color: colorScheme.primary,
                    ),
              ),
              ClipRRect(
                borderRadius: AppRadius.standard,
                child: SizedBox(
                  height: 6,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: colorScheme.onSurface.withValues(alpha: 0.08),
                        ),
                      ),
                      Positioned.fill(
                        child: FractionallySizedBox(
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: share.clamp(0.0, 1.0),
                          child: ColoredBox(
                            color: isFastest
                                ? colorScheme.primary
                                : colorScheme.primary.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                sample.samplesMs.length > 1
                    ? context.l10n.toolSampleCount(
                        sample.successRateLabel,
                        sample.samplesMs.map((ms) => '$ms ms').join(' / '),
                      )
                    : sample.successRateLabel,
                style: AppTextRole.supportingText.of(context),
              ),
            ] else ...[
              Text(
                context.l10n.toolAllFailed('${sample.attempts}'),
                style: AppTextRole.supportingText
                    .of(context)
                    .copyWith(color: colorScheme.error),
              ),
              if (sample.message case final message?)
                Text(
                  message,
                  style: AppTextRole.supportingText
                      .of(context)
                      .copyWith(color: colorScheme.error),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
