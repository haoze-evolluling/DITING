part of 'requests_page.dart';

(Color, IconData) requestStatusStyle(BuildContext context, RequestStatus status) {
  final colorScheme = context.colorScheme;
  return switch (status) {
    RequestStatus.passed => (colorScheme.success, TablerIcons.circle_check),
    RequestStatus.rewritten => (colorScheme.primary, TablerIcons.pencil),
    RequestStatus.blocked => (colorScheme.warning, TablerIcons.ban),
    RequestStatus.error => (colorScheme.error, TablerIcons.alert_circle),
    RequestStatus.bypassed => (colorScheme.onSurfaceVariant, TablerIcons.arrows_shuffle),
    RequestStatus.all => (colorScheme.onSurfaceVariant, TablerIcons.info_circle),
  };
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _timeOfDay(int timestamp) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}:'
      '${_twoDigits(time.second)}';
}

String _stampOf(int timestamp) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${time.year}-${_twoDigits(time.month)}-${_twoDigits(time.day)} '
      '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}:'
      '${_twoDigits(time.second)}';
}

class RequestRow extends StatelessWidget {
  const RequestRow({super.key, required this.request, required this.onTap});

  final ObservedRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final (statusColor, statusGlyph) = requestStatusStyle(
      context,
      request.status,
    );
    final title = request.title.isEmpty ? '—' : request.title;

    return ListItem(
      leading: Icon(statusGlyph, size: 20, color: statusColor),
      title: Row(
        children: [
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(
            _timeOfDay(request.timestamp),
            style: AppTextRole.supportingText
                .of(context)
                .copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontFeatures: appTabularFigures,
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
              style: AppTextRole.supportingText
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
            if (request.packageName case final packageName?
                when packageName.isNotEmpty)
              Text(
                packageName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextRole.supportingText
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
                style: AppTextRole.supportingText
                    .of(context)
                    .copyWith(
                      color: elapsed >= 600
                          ? colorScheme.warning
                          : colorScheme.onSurfaceVariant,
                      fontFeatures: appTabularFigures,
                    ),
              ),
          ],
        ),
      ),
      trailing: Icon(
        TablerIcons.chevron_right,
        size: 18,
        color: colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
