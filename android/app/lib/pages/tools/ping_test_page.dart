part of 'tools_page.dart';

/// Ping page: target, count and real ICMP results from `DiagnosticsRunner.ping`.
/// `success=false` renders a failure, `measuredWithFallback=true` means the latency is TCP
/// handshake time, not ICMP RTT.
class PingTestPage extends ConsumerStatefulWidget {
  const PingTestPage({super.key});

  @override
  ConsumerState<PingTestPage> createState() => _PingTestPageState();
}

class _PingTestPageState extends ConsumerState<PingTestPage> {
  final _target = TextEditingController();
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
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final flags = ref.watch(networkToolFlagsProvider);
    final result = _result;
    final showEmpty = result == null && !_running && _hostError == null;
    return CommonScaffold(
      title: l10n.toolPing,
      body: PageBody(
        children: [
          _ToolInputCard(
            child: _ToolField(
              controller: _target,
              hintText: l10n.toolInputHostOrIp,
              glyph: AppGlyphs.target,
              enabled: !_running,
              onSubmitted: (_) => _run(),
            ),
          ),
          // Same count options as the legacy `PingSection`: 4 and 10 only.
          const SizedBox(height: 12),
          generateSection(
            title: l10n.toolPing,
            items: [
              ListItem<int>.options(
                leading: const GlyphIcon(AppGlyphs.send),
                title: Text(l10n.toolPing),
                value: _count,
                options: const [4, 10],
                textBuilder: (count) =>
                    count == 10 ? l10n.toolPingCount10 : l10n.toolPingCount4,
                onChanged: (count) {
                  if (!_running) {
                    setState(() => _count = count.clamp(1, 20));
                  }
                },
              ),
            ],
          ),
          generateSection(
            title: l10n.toolPingOptions,
            items: [
              _ViaTunnelRow(
                storageKey: pingViaTunnelKey,
                title: l10n.toolViaTunnel,
                subtitle: l10n.toolViaTunnelPingBody,
                value: flags.pingViaTunnel,
                enabled: !_running,
              ),
            ],
          ),
          _RunButton(
            glyph: AppGlyphs.send,
            label: l10n.toolStartPing,
            runningLabel: l10n.toolPinging,
            running: _running,
            onPressed: _run,
          ),
          if (_hostError case final error?)
            _ToolNotice(text: error, isError: true, glyph: AppGlyphs.error),
          if (showEmpty)
            _ToolEmptyCard(
              glyph: AppGlyphs.connections,
              title: l10n.toolNotRunTitle,
              body: l10n.toolPingEmpty,
            ),
          if (result != null) ...[
            if (result.measuredWithFallback)
              _ToolNotice(text: l10n.toolTcpFallback, glyph: AppGlyphs.warning),
            if (!result.success)
              _ToolNotice(
                text: result.message ?? l10n.toolPingFailed,
                isError: true,
                glyph: AppGlyphs.error,
              ),
            _ToolSection(
              title: l10n.toolPingResults,
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
                  label: l10n.toolAddressFamily,
                  value: result.addressFamily ?? '—',
                ),
                KeyValueRow(
                  label: l10n.toolSentReceived,
                  value: '${result.transmitted} / ${result.received}',
                  tabular: true,
                ),
                KeyValueRow(
                  label: l10n.toolPacketLoss,
                  value: '${result.lossPercent.toStringAsFixed(1)} %',
                  tabular: true,
                ),
                KeyValueRow(
                  label: l10n.toolMinAvgMax,
                  value:
                      '${_msText(result.minMs)} / ${_msText(result.avgMs)} / '
                      '${_msText(result.maxMs)}',
                  tabular: true,
                ),
                KeyValueRow(
                  label: l10n.toolJitter,
                  value: _msText(result.jitterMs),
                  tabular: true,
                ),
              ],
              footer: result.success ? l10n.toolJitterFooter : null,
            ),
            if (result.replies.isNotEmpty)
              generateSection(
                title: l10n.toolPingReplies,
                items: [
                  for (final reply in result.replies)
                    ListItem(
                      leading: GlyphIcon(
                        reply.ok ? AppGlyphs.checkCircle : AppGlyphs.error,
                        size: 20,
                        color: reply.ok
                            ? colorScheme.success
                            : colorScheme.error,
                      ),
                      title: Text(l10n.toolPacketN('${reply.sequence}')),
                      trailing: Text(
                        reply.ok
                            ? _msText(reply.elapsedMs)
                            : (reply.error ?? l10n.toolTimeout),
                        style: AppTextStyle.subheadline
                            .of(context)
                            .copyWith(
                              fontFeatures: appTabularFigures,
                              color: reply.ok
                                  ? colorScheme.onSurface
                                  : colorScheme.error,
                            ),
                      ),
                    ),
                ],
              ),
            PageIntroText(
              text: l10n.toolPingSummary(
                '${result.transmitted}',
                '${result.transmitted - result.received}',
              ),
            ),
          ],
          ListFooter(text: l10n.toolPingFooter),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
