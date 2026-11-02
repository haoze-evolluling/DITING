part of 'tools_page.dart';

/// DNS lookup panel backed by `DiagnosticsRunner.lookupDns`. Server mode is `SYSTEM` or `CUSTOM`
/// (real UDP query); `viaTunnel` asks the tunnel engine. Every result carries its `source`.
class _DnsLookupPanel extends ConsumerStatefulWidget {
  _DnsLookupPanel();

  @override
  ConsumerState<_DnsLookupPanel> createState() => _DnsLookupPanelState();
}

enum _DnsServerMode {
  system,
  custom;

  String label(AppL10n l10n) => switch (this) {
    system => l10n.toolDnsSystem,
    custom => l10n.toolDnsCustom,
  };
}

class _DnsLookupPanelState extends ConsumerState<_DnsLookupPanel> {
  final _domain = TextEditingController(text: '');
  final _server = TextEditingController(text: '');
  var _running = false;
  var _ipv4 = true;
  var _serverMode = _DnsServerMode.system;
  DnsLookupResult? _result;
  String? _hostError;

  @override
  void dispose() {
    _domain.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) {
      return;
    }
    final resolved = resolveProbeHost(_domain.text);
    if (resolved.error != null) {
      setState(() => _hostError = resolved.error);
      return;
    }
    final viaTunnel = ref.read(networkToolFlagsProvider).dnsLookupViaTunnel;
    // Only the custom non-tunnel case carries a server; the rest use the system resolver.
    final server = !viaTunnel && _serverMode == _DnsServerMode.custom
        ? _server.text.trim()
        : null;
    // An empty custom server is treated as "system" natively, so reject it before the
    // request: the user would think they tested their own server.
    if (server != null && server.isEmpty) {
      setState(() => _hostError = context.l10n.toolCustomDnsError);
      return;
    }
    setState(() {
      _hostError = null;
      _running = true;
      _result = null;
    });
    final result = await ref
        .read(diagnosticsRunnerProvider)
        .lookupDns(
          resolved.host,
          viaTunnel: viaTunnel,
          ipv4: _ipv4,
          server: server,
        );
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
    final result = _result;
    // In tunnel mode the tunnel picks the server, so the switcher is hidden rather than
    // disabled: a greyed control implies it becomes usable later.
    final showServerMode = !flags.dnsLookupViaTunnel;
    return PageBody(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _ToolField(
            controller: _domain,
            hintText: context.l10n.toolInputDomain,
            glyph: AppGlyphs.language,
            enabled: !_running,
            onSubmitted: (_) => _run(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedControl<bool>(
            segments: const [(true, 'IPv4 (A)'), (false, 'IPv6 (AAAA)')],
            value: _ipv4,
            onChanged: (value) {
              if (!_running) {
                setState(() => _ipv4 = value);
              }
            },
          ),
        ),
        if (showServerMode) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedControl<_DnsServerMode>(
              segments: [
                for (final mode in _DnsServerMode.values)
                  (mode, mode.label(context.l10n)),
              ],
              value: _serverMode,
              onChanged: (mode) {
                if (!_running) {
                  setState(() => _serverMode = mode);
                }
              },
            ),
          ),
          if (_serverMode == _DnsServerMode.custom)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _ToolField(
                controller: _server,
                hintText: context.l10n.toolCustomDnsHint,
                glyph: AppGlyphs.dns,
                enabled: !_running,
                onSubmitted: (_) => _run(),
              ),
            ),
        ],
        generateSection(
          title: context.l10n.toolQueryOptions,
          items: [
            _ViaTunnelRow(
              storageKey: dnsLookupViaTunnelKey,
              title: context.l10n.toolViaTunnel,
              subtitle: context.l10n.toolViaTunnelDnsBody,
              value: flags.dnsLookupViaTunnel,
              enabled: !_running,
            ),
          ],
        ),
        _RunButton(
          glyph: AppGlyphs.search,
          label: context.l10n.toolStartQuery,
          runningLabel: context.l10n.toolQuerying,
          running: _running,
          onPressed: _run,
        ),
        if (_hostError case final error?)
          _ToolNotice(text: error, isError: true, glyph: AppGlyphs.error),
        if (result != null) ...[
          if (result.error != null)
            _ToolNotice(
              text: result.error!,
              isError: true,
              glyph: AppGlyphs.error,
            ),
          _ToolSection(
            rows: [
              KeyValueRow(label: context.l10n.toolQueryDomain, value: result.domain, monospace: true),
              KeyValueRow(
                label: context.l10n.toolRecordType,
                value: _ipv4 ? 'A（IPv4）' : 'AAAA（IPv6）',
              ),
              KeyValueRow(
                label: context.l10n.toolDnsServers,
                value: _serverLabel(flags.dnsLookupViaTunnel),
                monospace: true,
              ),
              KeyValueRow(label: context.l10n.toolAnswerSource, value: dnsSourceLabel(result.source)),
              KeyValueRow(
                label: context.l10n.toolElapsed,
                value: _msText(result.elapsedMs),
                monospace: true,
              ),
              KeyValueRow(
                label: context.l10n.toolAnswerCount,
                value: '${result.answers.length}',
                monospace: true,
              ),
            ],
            footer: result.source == 'blocked'
                ? context.l10n.toolDnsBlockedBody
                : null,
          ),
          if (result.answers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: CommonCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final answer in result.answers)
                      KeyValueRow(
                        label: '${answer.recordType} · TTL ${answer.ttl}s',
                        value: answer.value,
                        monospace: true,
                      ),
                  ],
                ),
              ),
            )
          else
            _ToolNotice(
              text: context.l10n.toolDnsNoAnswers,
              glyph: AppGlyphs.warning,
            ),
        ],
        ListFooter(text: context.l10n.toolDnsFooter),
        const SizedBox(height: 24),
      ],
    );
  }

  /// Who this query actually asked; it must be spelled out, since after editing the server
  /// field without re-running the result still belongs to the previous server.
  String _serverLabel(bool viaTunnel) {
    if (viaTunnel) return context.l10n.toolTunnelEngine;
    if (_serverMode == _DnsServerMode.custom) return _server.text.trim();
    // The system's address is not part of the result (the native side returns only the
    // answer), so say so rather than inventing one.
    return context.l10n.toolDnsSystem;
  }
}
