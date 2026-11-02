part of 'requests_page.dart';

/// Six status tiers, not three: rewritten and bypassed are not failures, and both color
/// and glyph carry the meaning so color-blind users can tell them apart.
(Color, Glyph) requestStatusStyle(BuildContext context, RequestStatus status) {
  final colorScheme = context.colorScheme;
  return switch (status) {
    RequestStatus.passed => (colorScheme.success, AppGlyphs.checkCircle),
    RequestStatus.rewritten => (colorScheme.primary, AppGlyphs.edit),
    RequestStatus.blocked => (colorScheme.warning, AppGlyphs.block),
    RequestStatus.error => (colorScheme.error, AppGlyphs.error),
    RequestStatus.bypassed => (colorScheme.onSurfaceVariant, AppGlyphs.shuffle),
    RequestStatus.all => (colorScheme.onSurfaceVariant, AppGlyphs.info),
  };
}

/// Time of day as `HH:mm:ss`; the date belongs to the header card.
String _timeOfDay(int timestamp) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

/// Full timestamp as `yyyy-MM-dd HH:mm:ss`, same format as upstream.
String _stampOf(int timestamp) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

class RequestRow extends StatelessWidget {
  const RequestRow({super.key, required this.request, required this.onTap});

  final ObservedRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final (statusColor, statusGlyph) = requestStatusStyle(context, request.status);
    // authority can be null when TLS fails early, and title is then an empty string.
    // An empty Text renders as a hole, so fall back to a dash.
    final title = request.title.isEmpty ? '—' : request.title;

    return ListItem(
      leading: GlyphIcon(statusGlyph, size: 20, color: statusColor),
      title: Row(
        children: [
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(
            _timeOfDay(request.timestamp),
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontFamily: appMonospaceFontFamily,
                ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              request.source.label,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
            if (request.packageName case final packageName?
                when packageName.isNotEmpty)
              Text(
                packageName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            TonalChip(
              label: request.status.label,
              color: statusColor.withValues(alpha: 0.14),
              foregroundColor: statusColor,
            ),
            if (request.elapsedMs case final elapsed?)
              Text(
                obsFormatLatency(elapsed, context.l10n),
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(
                      color: elapsed >= 600
                          ? colorScheme.warning
                          : colorScheme.onSurfaceVariant,
                      fontFamily: appMonospaceFontFamily,
                    ),
              ),
          ],
        ),
      ),
      trailing: GlyphIcon(
        AppGlyphs.chevronForward,
        size: 18,
        color: colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
