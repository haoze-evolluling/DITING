part of 'tools_page.dart';

/// Traceroute page with a per-hop list from `DiagnosticsRunner.traceRoute`. Hops arrive in
/// one batch: the legacy progressive callbacks cannot survive Flutter rebuilds.
class TraceroutePage extends ConsumerStatefulWidget {
  const TraceroutePage({super.key});

  @override
  ConsumerState<TraceroutePage> createState() => _TraceroutePageState();
}

class _TraceroutePageState extends ConsumerState<TraceroutePage> {
  final _target = TextEditingController();
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
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final flags = ref.watch(networkToolFlagsProvider);
    final result = _result;
    final showEmpty = result == null && !_running && _hostError == null;
    return CommonScaffold(
      title: l10n.toolTraceroute,
      body: PageBody(
        children: [
          PageIntroCard(text: l10n.toolTracerouteDesc),
          _ToolInputCard(
            child: _ToolField(
              controller: _target,
              hintText: l10n.toolInputHostOrIp,
              glyph: AppGlyphs.target,
              enabled: !_running,
              onSubmitted: (_) => _run(),
            ),
          ),
          // Same hop options as the legacy `TracerouteSection`: 15 and 30, defaulting to 15.
          const SizedBox(height: 12),
          generateSection(
            items: [
              ListItem<int>.options(
                leading: const GlyphIcon(AppGlyphs.connections),
                title: Text(l10n.toolTraceHops),
                value: _maxHops,
                options: const [15, 30],
                textBuilder: (hops) =>
                    hops == 30 ? l10n.toolTraceHops30 : l10n.toolTraceHops15,
                onChanged: (hops) {
                  if (!_running) {
                    setState(() => _maxHops = hops.clamp(1, 30));
                  }
                },
              ),
            ],
          ),
          generateSection(
            title: l10n.toolTraceOptions,
            items: [
              _ViaTunnelRow(
                storageKey: tracerouteViaTunnelKey,
                title: l10n.toolViaTunnel,
                subtitle: l10n.toolViaTunnelPingBody,
                value: flags.tracerouteViaTunnel,
                enabled: !_running,
              ),
            ],
          ),
          _RunButton(
            glyph: AppGlyphs.split,
            label: l10n.toolStartTrace,
            runningLabel: l10n.toolTracing,
            running: _running,
            onPressed: _run,
          ),
          if (_hostError case final error?)
            _ToolNotice(text: error, isError: true, glyph: AppGlyphs.error),
          if (showEmpty)
            _ToolEmptyCard(
              glyph: AppGlyphs.split,
              title: l10n.toolNotRunTitle,
              body: l10n.toolTraceEmpty,
            ),
          if (result != null) ...[
            if (!result.success && !result.cancelled)
              _ToolNotice(
                text: result.message ?? l10n.toolTraceFailed,
                isError: true,
                glyph: AppGlyphs.error,
              ),
            if (result.cancelled)
              _ToolNotice(text: l10n.toolTraceCancelled, glyph: AppGlyphs.info),
            _ToolSection(
              title: l10n.toolTraceResults,
              rows: [
                KeyValueRow(
                  label: l10n.toolTarget,
                  value: result.target,
                  tabular: true,
                ),
                KeyValueRow(
                  label: l10n.toolResolvedAddress,
                  value: result.resolvedAddress ?? '—',
                  tabular: true,
                ),
                KeyValueRow(
                  label: l10n.toolHopCount,
                  value: l10n.toolHopCountValue(
                    '${result.hops.length}',
                    '$_maxHops',
                  ),
                  tabular: true,
                ),
              ],
            ),
            if (result.hops.isNotEmpty)
              generateSection(
                title: l10n.toolTraceHops,
                items: [
                  for (final hop in result.hops)
                    ListItem(
                      leading: SizedBox(
                        width: 24,
                        child: Text(
                          '${hop.hop}',
                          textAlign: TextAlign.center,
                          style: AppTextStyle.caption1
                              .of(context)
                              .copyWith(
                                fontFeatures: appTabularFigures,
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                      title: Text(
                        hop.address ?? '* * *',
                        style: AppTextStyle.subheadline
                            .of(context)
                            .copyWith(
                              fontFeatures: appTabularFigures,
                              color: hop.responded
                                  ? (hop.reachedTarget
                                        ? colorScheme.success
                                        : colorScheme.onSurface)
                                  : colorScheme.onSurfaceVariant,
                            ),
                      ),
                      trailing: Text(
                        hop.responded
                            ? _msText(hop.elapsedMs)
                            : l10n.toolNoResponse,
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
          ],
          ListFooter(text: l10n.toolTraceFooter),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
