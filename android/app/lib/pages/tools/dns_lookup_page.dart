part of 'tools_page.dart';

/// DNS lookup page backed by `DiagnosticsRunner.lookupDns`. Server mode is `SYSTEM` or `CUSTOM`
/// (real UDP query); `viaTunnel` asks the tunnel engine. Every result carries its `source`.
class DnsLookupPage extends ConsumerStatefulWidget {
  const DnsLookupPage({super.key});

  @override
  ConsumerState<DnsLookupPage> createState() => _DnsLookupPageState();
}

enum _DnsServerMode {
  system,
  custom;

  String label(AppL10n l10n) => switch (this) {
    system => l10n.toolDnsSystem,
    custom => l10n.toolDnsCustom,
  };
}

class _DnsLookupPageState extends ConsumerState<DnsLookupPage> {
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
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final flags = ref.watch(networkToolFlagsProvider);
    final result = _result;
    // In tunnel mode the tunnel picks the server, so the switcher is hidden rather than
    // disabled: a greyed control implies it becomes usable later.
    final showServerMode = !flags.dnsLookupViaTunnel;
    final showEmpty = result == null && !_running && _hostError == null;
    return CommonScaffold(
      title: l10n.toolDnsLookup,
      body: PageBody(
        children: [
          PageIntroCard(text: l10n.toolDnsLookupDesc),
          _ToolInputCard(
            child: _ToolField(
              controller: _domain,
              hintText: l10n.toolInputDomain,
              glyph: AppGlyphs.language,
              enabled: !_running,
              onSubmitted: (_) => _run(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedControl<bool>(
              segments: const [(true, 'A (IPv4)'), (false, 'AAAA (IPv6)')],
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
                    (mode, mode.label(l10n)),
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
              _ToolInputCard(
                child: _ToolField(
                  controller: _server,
                  hintText: l10n.toolCustomDnsHint,
                  glyph: AppGlyphs.dns,
                  enabled: !_running,
                  onSubmitted: (_) => _run(),
                ),
              ),
          ],
          generateSection(
            title: l10n.toolQueryOptions,
            items: [
              _ViaTunnelRow(
                storageKey: dnsLookupViaTunnelKey,
                title: l10n.toolViaTunnel,
                subtitle: l10n.toolViaTunnelDnsBody,
                value: flags.dnsLookupViaTunnel,
                enabled: !_running,
              ),
            ],
          ),
          _RunButton(
            glyph: AppGlyphs.search,
            label: l10n.toolStartQuery,
            runningLabel: l10n.toolQuerying,
            running: _running,
            onPressed: _run,
          ),
          if (_hostError case final error?)
            _ToolNotice(text: error, isError: true, glyph: AppGlyphs.error),
          if (showEmpty)
            _ToolEmptyCard(
              glyph: AppGlyphs.dns,
              title: l10n.toolNotRunTitle,
              body: l10n.toolDnsEmpty,
            ),
          if (result != null) ...[
            if (result.error != null)
              _ToolNotice(
                text: result.error!,
                isError: true,
                glyph: AppGlyphs.error,
              ),
            _ToolSection(
              title: l10n.toolDnsResults,
              rows: [
                KeyValueRow(
                  label: l10n.toolQueryDomain,
                  value: result.domain,
                  tabular: true,
                ),
                KeyValueRow(
                  label: l10n.toolRecordType,
                  value: _ipv4 ? 'A (IPv4)' : 'AAAA (IPv6)',
                ),
                KeyValueRow(
                  label: l10n.toolDnsServers,
                  value: _serverLabel(flags.dnsLookupViaTunnel),
                  tabular: true,
                ),
                KeyValueRow(
                  label: l10n.toolAnswerSource,
                  value: dnsSourceLabel(result.source),
                ),
                KeyValueRow(
                  label: l10n.toolElapsed,
                  value: _msText(result.elapsedMs),
                  tabular: true,
                ),
                KeyValueRow(
                  label: l10n.toolAnswerCount,
                  value: '${result.answers.length}',
                  tabular: true,
                ),
              ],
              footer: result.source == 'blocked'
                  ? l10n.toolDnsBlockedBody
                  : null,
            ),
            if (result.answers.isNotEmpty)
              generateSection(
                title: l10n.toolDnsAnswers,
                items: [
                  for (final answer in result.answers)
                    ListItem(
                      leading: const GlyphIcon(AppGlyphs.dns, size: 20),
                      title: Text(
                        answer.value,
                        style: AppTextStyle.subheadline
                            .of(context)
                            .copyWith(
                              fontFeatures: appTabularFigures,
                              color: colorScheme.onSurface,
                            ),
                      ),
                      subtitle: Text(
                        '${answer.recordType} · TTL ${answer.ttl}s',
                      ),
                    ),
                ],
              )
            else if (result.error == null)
              _ToolNotice(
                text: l10n.toolDnsNoAnswers,
                glyph: AppGlyphs.warning,
              ),
          ],
          ListFooter(text: l10n.toolDnsFooter),
          const SizedBox(height: 24),
        ],
      ),
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
