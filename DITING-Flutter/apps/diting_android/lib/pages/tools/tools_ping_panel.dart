part of 'tools_page.dart';

/// Ping panel: target, count and real ICMP results from `DiagnosticsRunner.ping`.
/// `success=false` renders a failure, `measuredWithFallback=true` means the latency is TCP
/// handshake time, not ICMP RTT.
class _PingPanel extends ConsumerStatefulWidget {
  const _PingPanel();

  @override
  ConsumerState<_PingPanel> createState() => _PingPanelState();
}

class _PingPanelState extends ConsumerState<_PingPanel> {
  final _target = TextEditingController(text: '');
  var _count = 4;
  var _running = false;
  PingSummary? _result;
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
    final summary = await ref
        .read(diagnosticsRunnerProvider)
        .ping(resolved.host, count: _count);
    if (!mounted) {
      return;
    }
    setState(() {
      _running = false;
      _result = summary;
    });
  }

  @override
  Widget build(BuildContext context) {
    final flags = ref.watch(networkToolFlagsProvider);
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
        // Same count options as the legacy `PingSection`: 4 and 10 only.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedControl<int>(
            segments: [(4, context.l10n.toolPingCount4), (10, context.l10n.toolPingCount10)],
            value: _count,
            onChanged: (count) {
              if (!_running) {
                setState(() => _count = count.clamp(1, 20));
              }
            },
          ),
        ),
        generateSection(
          title: context.l10n.toolPingOptions,
          items: [
            _ViaTunnelRow(
              storageKey: pingViaTunnelKey,
              title: context.l10n.toolViaTunnel,
              subtitle: context.l10n.toolViaTunnelPingBody,
              value: flags.pingViaTunnel,
              enabled: !_running,
            ),
          ],
        ),
        _RunButton(
          glyph: AppGlyphs.send,
          label: context.l10n.toolStartPing,
          runningLabel: context.l10n.toolPinging,
          running: _running,
          onPressed: _run,
        ),
        if (_hostError case final error?)
          _ToolNotice(text: error, isError: true, glyph: AppGlyphs.error),
        if (result != null) ...[
          if (result.measuredWithFallback)
            _ToolNotice(
              text:
                  context.l10n.toolTcpFallback,
              glyph: AppGlyphs.warning,
            ),
          if (!result.success)
            _ToolNotice(
              text: result.message ?? context.l10n.toolPingFailed,
              isError: true,
              glyph: AppGlyphs.error,
            ),
          _ToolSection(
            rows: [
              KeyValueRow(label: context.l10n.toolTarget, value: result.target, monospace: true),
              KeyValueRow(
                label: context.l10n.toolResolvedAddress,
                value: result.resolvedAddress ?? '—',
                monospace: true,
              ),
              KeyValueRow(label: context.l10n.toolAddressFamily, value: result.addressFamily ?? '—'),
              KeyValueRow(
                label: context.l10n.toolSentReceived,
                value: '${result.transmitted} / ${result.received}',
                monospace: true,
              ),
              KeyValueRow(
                label: context.l10n.toolPacketLoss,
                value: '${result.lossPercent.toStringAsFixed(1)} %',
                monospace: true,
              ),
              KeyValueRow(
                label: context.l10n.toolMinAvgMax,
                value:
                    '${_msText(result.minMs)} / ${_msText(result.avgMs)} / '
                    '${_msText(result.maxMs)}',
                monospace: true,
              ),
              KeyValueRow(
                label: context.l10n.toolJitter,
                value: _msText(result.jitterMs),
                monospace: true,
              ),
            ],
            footer: result.success ? context.l10n.toolJitterFooter : null,
          ),
          if (result.replies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: CommonCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final reply in result.replies)
                      KeyValueRow(
                        label: context.l10n.toolPacketN('${reply.sequence}'),
                        value: reply.ok
                            ? _msText(reply.elapsedMs)
                            : (reply.error ?? context.l10n.toolTimeout),
                        monospace: true,
                      ),
                  ],
                ),
              ),
            ),
          PageIntroText(
            text:
                context.l10n.toolPingSummary(
                  '${result.transmitted}',
                  '${result.transmitted - result.received}',
                ),
          ),
        ],
        ListFooter(
          text: context.l10n.toolPingFooter,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
