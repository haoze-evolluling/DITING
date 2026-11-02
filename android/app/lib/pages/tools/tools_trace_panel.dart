part of 'tools_page.dart';

/// Traceroute panel with a per-hop list from `DiagnosticsRunner.traceRoute`. Hops arrive in
/// one batch: the legacy progressive callbacks cannot survive Flutter rebuilds.
class _TraceroutePanel extends ConsumerStatefulWidget {
  const _TraceroutePanel();

  @override
  ConsumerState<_TraceroutePanel> createState() => _TraceroutePanelState();
}

class _TraceroutePanelState extends ConsumerState<_TraceroutePanel> {
  final _target = TextEditingController(text: '');
  var _maxHops = 15;
  var _running = false;
  TraceResult? _result;
  String? _hostError;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) {
      return;
    }
    final resolved = resolveProbeHost(_target.text);
    if (resolved.error != null) {
      setState(() => _hostError = resolved.error);
      return;
    }
    setState(() {
      _hostError = null;
      _running = true;
      _result = null;
    });
    final result = await ref
        .read(diagnosticsRunnerProvider)
        .traceRoute(resolved.host, maxHops: _maxHops);
    if (!mounted) {
      return;
    }
    setState(() {
      _running = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(networkToolFlagsProvider);
    final colorScheme = context.colorScheme;
    final result = _result;
    return PageBody(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _ToolField(
            controller: _target,
            hintText: context.l10n.toolInputHostOrIp,
            glyph: AppGlyphs.target,
            enabled: !_running,
            onSubmitted: (_) => _run(),
          ),
        ),
        // Same hop options as the legacy `TracerouteSection`: 15 and 30, defaulting to 15.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedControl<int>(
            segments: [(15, context.l10n.toolTraceHops15), (30, context.l10n.toolTraceHops30)],
            value: _maxHops,
            onChanged: (hops) {
              if (!_running) {
                setState(() => _maxHops = hops.clamp(1, 30));
              }
            },
          ),
        ),
        generateSection(
          title: context.l10n.toolTraceOptions,
          items: [
            _ViaTunnelRow(
              storageKey: tracerouteViaTunnelKey,
              title: context.l10n.toolViaTunnel,
              subtitle: context.l10n.toolViaTunnelPingBody,
              value: flags.tracerouteViaTunnel,
              enabled: !_running,
            ),
          ],
        ),
        _RunButton(
          glyph: AppGlyphs.split,
          label: context.l10n.toolStartTrace,
          runningLabel: context.l10n.toolTracing,
          running: _running,
          onPressed: _run,
        ),
        if (_hostError case final error?)
          _ToolNotice(text: error, isError: true, glyph: AppGlyphs.error),
        if (result != null) ...[
          if (!result.success && !result.cancelled)
            _ToolNotice(
              text: result.message ?? context.l10n.toolTraceFailed,
              isError: true,
              glyph: AppGlyphs.error,
            ),
          if (result.cancelled)
            _ToolNotice(text: context.l10n.toolTraceCancelled, glyph: AppGlyphs.info),
          _ToolSection(
            rows: [
              KeyValueRow(label: context.l10n.toolTarget, value: result.target, monospace: true),
              KeyValueRow(
                label: context.l10n.toolResolvedAddress,
                value: result.resolvedAddress ?? '—',
                monospace: true,
              ),
              KeyValueRow(
                label: context.l10n.toolHopCount,
                value: context.l10n.toolHopCountValue(
                  '${result.hops.length}',
                  '$_maxHops',
                ),
                monospace: true,
              ),
            ],
          ),
          if (result.hops.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: CommonCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final hop in result.hops)
                      ListItem(
                        leading: SizedBox(
                          width: 24,
                          child: Text(
                            '${hop.hop}',
                            textAlign: TextAlign.center,
                            style: AppTextStyle.caption1
                                .of(context)
                                .copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                        title: Text(
                          hop.address ?? '* * *',
                          style: AppTextStyle.subheadline
                              .of(context)
                              .copyWith(
                                fontFamily: appMonospaceFontFamily,
                                color: hop.responded
                                    ? (hop.reachedTarget
                                          ? colorScheme.success
                                          : colorScheme.onSurface)
                                    : colorScheme.onSurfaceVariant,
                              ),
                        ),
                        trailing: Text(
                          hop.responded ? _msText(hop.elapsedMs) : context.l10n.toolNoResponse,
                          style: AppTextStyle.caption1
                              .of(context)
                              .copyWith(
                                color: hop.responded
                                    ? colorScheme.onSurfaceVariant
                                    : colorScheme.warning,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
        ListFooter(
          text:
              context.l10n.toolTraceFooter,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
