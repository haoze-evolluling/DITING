part of 'tools_page.dart';

/// Speed test tab measuring real DNS query latency (legacy `DnsSpeedTestSection`). A missing
/// channel
/// disables the button instead of faking numbers; failed entries never win the fastest badge.
class _SpeedTestPanel extends ConsumerStatefulWidget {
  const _SpeedTestPanel();

  @override
  ConsumerState<_SpeedTestPanel> createState() => _SpeedTestPanelState();
}

class _SpeedTestPanelState extends ConsumerState<_SpeedTestPanel> {
  final _domain = TextEditingController();

  var _domainBound = false;

  @override
  void dispose() {
    _domain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

    return PageBody(
      children: [
        if (available.isLoading)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _ToolNotice(text: context.l10n.toolSpeedChecking),
          ),
        if (unavailable)
          _ToolNotice(
            text:
                context.l10n.toolSpeedUnsupported,
            isError: true,
            glyph: AppGlyphs.warning,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: CommonCard(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: _ToolField(
              controller: _domain,
              hintText: context.l10n.toolSpeedDomainHint,
              glyph: AppGlyphs.language,
              enabled: !state.running && !unavailable,
              // Write back on every keystroke: `_run` reads the provider value, so a
              // controller-only change would test the previous domain.
              onChanged: (value) =>
                  ref.read(latencyDomainProvider.notifier).setDomain(value),
              onSubmitted: (_) => _run(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedControl<DnsLatencyProtocol>(
            segments: [for (final item in protocols) (item, item.label)],
            value: protocol,
            onChanged: (value) {
              if (!state.running) {
                ref.read(latencyProtocolProvider.notifier).select(value);
              }
            },
          ),
        ),
        generateSection(
          title: context.l10n.toolSpeedProviders,
          items: [
            if (providers.isEmpty)
              ListItem(
                leading: const GlyphIcon(AppGlyphs.info, size: 20),
                title: Text(context.l10n.toolNoProviders(protocol.label)),
                subtitle: Text(context.l10n.toolNoProvidersBody),
              )
            else
              for (final spec in providers)
                ListItem.checkbox(
                  value: selected.contains(spec.id),
                  leading: const GlyphIcon(AppGlyphs.dns, size: 20),
                  title: Text(spec.name),
                  subtitle: Text(latencyEndpointLabel(spec)),
                  onChanged: state.running
                      ? null
                      : (_) => ref
                            .read(latencySelectionProvider.notifier)
                            .toggle(spec.id),
                ),
          ],
          footer:
              context.l10n.toolSpeedSelectionNote,
        ),
        if (state.error case final error?)
          _ToolNotice(text: error, isError: true, glyph: AppGlyphs.error),
        _RunButton(
          glyph: AppGlyphs.speed,
          label: context.l10n.toolTestQueryTime,
          runningLabel: context.l10n.toolSpeedRunning,
          running: state.running,
          onPressed: unavailable || selected.isEmpty ? null : _run,
        ),
        if (!state.running && state.results.isEmpty && !unavailable)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: CommonCard(
              padding: EdgeInsets.all(16),
              child: Text(
                context.l10n.toolSpeedEmpty,
              ),
            ),
          ),
        if (state.results.isNotEmpty) ...[
          /// Rows go through `generateSection`, not a hand-rolled `CommonCard` + `Column`: `lib/ui`
          /// drives separators from `ItemPosition`, while `Divider(height: 0.5)` is a full logical
          /// pixel.
          generateSection(
            title: context.l10n.toolSpeedResults,
            items: [
              for (final (index, sample) in state.results.indexed)
                _SpeedResultRow(
                  sample: sample,
                  rank: index + 1,
                  isFastest: index == 0 && sample.success,
                  barMax: barMax,
                ),
            ],
            footer:
                context.l10n.toolSpeedResultsFooter(domain),
          ),
        ],
        ListFooter(
          text:
              context.l10n.toolSpeedFooter,
        ),
        const SizedBox(height: 24),
      ],
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

/// Rank, name, protocol badge, fastest badge, latency bar, success rate and sample count.
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
                  style: AppTextStyle.subheadline
                      .of(context, emphasized: true)
                      .copyWith(
                        fontFamily: appMonospaceFontFamily,
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
                  style: context.listTitleStyle,
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
              style: AppTextStyle.title3
                  .of(context, emphasized: true)
                  .copyWith(
                    fontFamily: appMonospaceFontFamily,
                    color: colorScheme.primary,
                  ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
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
                        child: ColoredBox(color: colorScheme.primary),
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
              style: context.listCaptionStyle,
            ),
          ] else ...[
            Text(
              context.l10n.toolAllFailed('${sample.attempts}'),
              style: context.listCaptionStyle.copyWith(
                color: colorScheme.error,
              ),
            ),
            if (sample.message case final message?)
              Text(
                message,
                style: context.listCaptionStyle.copyWith(
                  color: colorScheme.error,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
