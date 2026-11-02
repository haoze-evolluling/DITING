part of 'requests_page.dart';

/// Handling text, translating outcome and message into plain words. Wording follows the
/// upstream matchedRule switch; no invented categories.
String requestHandlingOf(ObservedRequest request, AppL10n l10n) {
  if (request.source == RequestSource.dns) {
    if (request.status == RequestStatus.bypassed) return l10n.obsBypassedDns;
    if (request.status == RequestStatus.blocked) return l10n.obsBlockedDns;
    if (request.status == RequestStatus.rewritten) return l10n.obsRewrittenDns;
    if (request.status == RequestStatus.error) return l10n.obsErrorDns;
    return l10n.obsPassedDns;
  }
  return switch (request.status) {
    RequestStatus.passed => l10n.obsPassedHttps,
    RequestStatus.rewritten => l10n.obsRewrittenHttps,
    RequestStatus.blocked => l10n.obsBlockedHttps,
    RequestStatus.bypassed => l10n.obsBypassedHttps,
    RequestStatus.error => l10n.obsErrorHttps,
    RequestStatus.all => '—',
  };
}

/// Matched rule text. An empty value gets an explanation rather than "none".
String requestRuleOf(ObservedRequest request, AppL10n l10n) {
  final rule = request.matchedRule?.trim();
  if (rule != null && rule.isNotEmpty) return rule;
  return request.source == RequestSource.https ? l10n.obsNoRuleHttps : l10n.obsNone;
}

/// Bare host of a record: drops the `TCP `/`UDP ` prefix of connection rows, the port and any
/// trailing dot. Null when the record carries no host at all.
String? requestHostOf(ObservedRequest request) {
  var text = request.title.trim();
  final lower = text.toLowerCase();
  if (lower.startsWith('tcp ') || lower.startsWith('udp ')) {
    text = text.substring(4).trim();
  }
  if (text.startsWith('[')) {
    final end = text.indexOf(']');
    return end > 1 ? text.substring(1, end) : null;
  }
  final colon = text.lastIndexOf(':');
  // A single colon followed by digits is a port; several colons mean a bare IPv6 address.
  if (colon > 0 &&
      text.indexOf(':') == colon &&
      int.tryParse(text.substring(colon + 1)) != null) {
    text = text.substring(0, colon);
  }
  text = text.replaceFirst(RegExp(r'\.+$'), '');
  return text.isEmpty ? null : text;
}

class RequestDetailSheet extends StatelessWidget {
  const RequestDetailSheet({
    super.key,
    required this.request,
    this.showAppLink = true,
  });

  final ObservedRequest request;

  /// Offers the page of this request's app; off when the sheet was opened from that page.
  final bool showAppLink;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final host = requestHostOf(request);
    final parsed = DnsLogMessage.parse(request.message);
    final (statusColor, statusGlyph) = requestStatusStyle(context, request.status);

    return CommonScaffold(
      title: context.l10n.obsRequestDetailTitle,
      body: PageBody(
        children: [
          DetailHeroCard(
            glyph: statusGlyph,
            color: statusColor,
            title: request.title.isEmpty ? '—' : request.title,
            subtitle: request.status.explanation,
            chips: [
              TonalChip(
                label: request.status.label,
                color: statusColor.withValues(alpha: 0.14),
                foregroundColor: statusColor,
              ),
              DetailMetaChip(label: request.source.label),
              if (request.cached) DetailMetaChip(label: context.l10n.obsCachedChip),
              DetailMetaChip(label: _stampOf(request.timestamp)),
            ],
          ),
          DomainActionRow(host: host),
          SectionBlock(
            title: context.l10n.obsBasicInfo,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: DetailInfoCard(
              children: [
                KeyValueRow(
                  label: context.l10n.obsTime,
                  value: _stampOf(request.timestamp),
                  monospace: true,
                ),
                KeyValueRow(label: context.l10n.obsSource, value: request.source.label),
                if (request.protocol case final protocol?
                    when protocol.isNotEmpty)
                  KeyValueRow(label: context.l10n.obsProtocol, value: protocol, monospace: true),
                if (request.packageName case final packageName?
                    when packageName.isNotEmpty)
                  KeyValueRow(
                    label: context.l10n.obsAppPackage,
                    value: packageName,
                    monospace: true,
                  ),
                if (request.packageName case final packageName?
                    when showAppLink && packageName.isNotEmpty)
                  ListItem(
                    title: Text(context.l10n.obsViewAppRequests),
                    trailing: GlyphIcon(
                      AppGlyphs.chevronForward,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    // Close the sheet first, otherwise coming back shows it over the list again.
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(ObservabilityPaths.appRequests(packageName));
                    },
                  ),
                if (parsed.resolved case final resolved?)
                  KeyValueRow(label: context.l10n.obsResolved, value: resolved, monospace: true),
                if (request.elapsedMs case final elapsed?)
                  KeyValueRow(
                    label: context.l10n.obsElapsed,
                    value: obsFormatLatency(elapsed, context.l10n),
                    monospace: true,
                  ),
                if (request.blockSubscriptionId case final id?)
                  KeyValueRow(label: context.l10n.obsBlockingSubscription, value: 'sub_$id', monospace: true),
              ],
            ),
          ),
          SectionBlock(
            title: context.l10n.obsRuleMatch,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: DetailInfoCard(
              children: [
                KeyValueRow(
                  label: context.l10n.obsRule,
                  value: requestRuleOf(request, context.l10n),
                  monospace: true,
                ),
                KeyValueRow(
                  label: context.l10n.obsHandling,
                  value: requestHandlingOf(request, context.l10n),
                ),
                if (parsed.error case final error?)
                  KeyValueRow(label: context.l10n.obsError, value: error, monospace: true),
              ],
            ),
          ),
          if (host != null) AgentAnalysisSection(domain: host),
          if (request.message case final message? when message.isNotEmpty)
            SectionBlock(
              title: context.l10n.obsRawRecord,
              footer: context.l10n.obsRawRecordFooter,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: CommonCard(
                padding: const EdgeInsets.all(14),
                inert: true,
                child: SelectableText(
                  message.split(',').map((part) => part.trim()).join('\n'),
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(
                        color: colorScheme.onSurface,
                        fontFamily: appMonospaceFontFamily,
                        height: 1.5,
                      ),
                ),
              ),
            ),
          ListFooter(
            text: request.status == RequestStatus.error
                ? context.l10n.obsFailedHint
                : context.l10n.obsRulesHint,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
