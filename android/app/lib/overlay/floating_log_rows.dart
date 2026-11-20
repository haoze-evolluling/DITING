library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/dns_query_repository.dart';
import 'package:diting_android/data/db/http_request_repository.dart';
import 'package:diting_android/pages/observability/observability_common.dart';
import 'package:diting_android/pages/observability/requests_page.dart'
    show requestHandlingOf, requestHostOf, requestRuleOf, requestStatusStyle;
import 'package:diting_android/state/observability_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

String floatingLogTime(int timestamp, {bool withDate = false}) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
  String two(int value) => value.toString().padLeft(2, '0');
  final clock = '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  return withDate
      ? '${time.year}-${two(time.month)}-${two(time.day)} $clock'
      : clock;
}

class FloatingLogBall extends StatelessWidget {
  const FloatingLogBall({super.key, required this.badge, required this.onTap});

  static const double size = 48;

  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: context.l10n.floatingLogOpen,
      child: SizedBox.square(
        dimension: size + 8,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Material(
              color: SurfaceLevel.floatingOf(colorScheme).colorOf(colorScheme),
              shape: AppShape.standard,
              elevation: 3,
              shadowColor: Colors.black54,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: SizedBox.square(
                  dimension: size,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Image.asset(
                      dark
                          ? 'packages/diting_shared/assets/images/icon_dark.webp'
                          : 'packages/diting_shared/assets/images/icon.webp',
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
            ),
            if (badge > 0)
              Positioned(
                top: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: colorScheme.error,
                      shape: AppShape.standard,
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: AppTextRole.badge
                          .of(context)
                          .copyWith(color: colorScheme.onError),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class FloatingLogFilterChip extends StatelessWidget {
  const FloatingLogFilterChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final foreground = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    return Material(
      color: selected
          ? colorScheme.secondaryContainer
          : context.raisedSurfaceLevel.colorOf(colorScheme),
      shape: AppShape.standard,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 5,
            children: [
              if (color case final dot?)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
              Text(
                label,
                style:
                    (selected
                            ? AppTextRole.sectionLabel
                            : AppTextRole.supportingText)
                        .of(context)
                        .copyWith(color: foreground),
              ),
              Text(
                '$count',
                style: AppTextRole.caption
                    .of(context)
                    .copyWith(
                      color: foreground.withValues(alpha: 0.75),
                      fontFeatures: appTabularFigures,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FloatingLogRow extends StatelessWidget {
  const FloatingLogRow({
    super.key,
    required this.request,
    required this.expanded,
    required this.onTap,
    required this.onCopy,
  });

  final ObservedRequest request;
  final bool expanded;
  final VoidCallback onTap;

  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final (statusColor, statusGlyph) = requestStatusStyle(
      context,
      request.status,
    );
    final title = request.title.isEmpty ? '—' : request.title;
    final caption = AppTextRole.caption
        .of(context)
        .copyWith(color: colorScheme.onSurfaceVariant);
    final meta = [
      request.source.label,
      if (request.packageName case final name? when name.isNotEmpty) name,
    ].join(' · ');

    return Material(
      color: expanded
          ? context.raisedSurfaceLevel.colorOf(colorScheme)
          : Colors.transparent,
      shape: AppShape.standard,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => onCopy(requestHostOf(request) ?? request.title),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                spacing: 8,
                children: [
                  GlyphIcon(statusGlyph, size: 16, color: statusColor),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: expanded ? 3 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextRole.body
                          .of(context)
                          .copyWith(color: colorScheme.onSurface),
                    ),
                  ),
                  Text(
                    floatingLogTime(request.timestamp),
                    style: caption.copyWith(fontFeatures: appTabularFigures),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 3),
                child: Row(
                  spacing: 6,
                  children: [
                    TonalChip(
                      label: request.status.label,
                      color: statusColor.withValues(alpha: 0.14),
                      foregroundColor: statusColor,
                    ),
                    Expanded(
                      child: Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: caption,
                      ),
                    ),
                    if (request.elapsedMs case final elapsed?)
                      Text(
                        obsFormatLatency(elapsed, context.l10n),
                        style: caption.copyWith(
                          fontFeatures: appTabularFigures,
                          color: elapsed >= 600 ? colorScheme.warning : null,
                        ),
                      ),
                  ],
                ),
              ),
              if (expanded) _Details(request: request, onCopy: onCopy),
            ],
          ),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.request, required this.onCopy});

  final ObservedRequest request;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final parsed = DnsLogMessage.parse(request.message);
    final host = requestHostOf(request);
    final lines = <(String, String)>[
      (l10n.obsTime, floatingLogTime(request.timestamp, withDate: true)),
      if (request.protocol case final protocol? when protocol.isNotEmpty)
        (l10n.obsProtocol, protocol),
      if (request.packageName case final name? when name.isNotEmpty)
        (l10n.obsAppPackage, name),
      if (parsed.resolved case final resolved?) (l10n.obsResolved, resolved),
      (l10n.obsRule, requestRuleOf(request, l10n)),
      (l10n.obsHandling, requestHandlingOf(request, l10n)),
      if (parsed.error case final error?) (l10n.obsError, error),
      if (request.cached) (l10n.obsCachedChip, '✓'),
    ];
    final colorScheme = context.colorScheme;
    final labelStyle = AppTextRole.caption
        .of(context)
        .copyWith(color: colorScheme.onSurfaceVariant);
    final valueStyle = AppTextRole.caption
        .of(context)
        .copyWith(color: colorScheme.onSurface);
    return Padding(
      padding: const EdgeInsets.only(left: 24, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          for (final (label, value) in lines)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 64, child: Text(label, style: labelStyle)),
                Expanded(child: Text(value, style: valueStyle)),
              ],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (host != null)
                _SmallButton(
                  glyph: AppGlyphs.copy,
                  label: l10n.floatingLogCopyDomain,
                  onPressed: () => onCopy(host),
                ),
              _SmallButton(
                glyph: AppGlyphs.textShort,
                label: l10n.floatingLogCopyRecord,
                onPressed: () => onCopy(_recordText(request, lines)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _recordText(
    ObservedRequest request,
    List<(String, String)> lines,
  ) => [
    request.title,
    '${request.source.label} · ${request.status.label}',
    for (final (label, value) in lines) '$label: $value',
    if (request.message case final message? when message.isNotEmpty) message,
  ].join('\n');
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.glyph,
    required this.label,
    required this.onPressed,
  });

  final Glyph glyph;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: AppTextRole.sectionLabel.of(context),
      ),
      icon: GlyphIcon(glyph, size: 16),
      label: Text(label),
    );
  }
}

const floatingLogStatuses = [
  RequestStatus.all,
  RequestStatus.blocked,
  RequestStatus.rewritten,
  RequestStatus.error,
  RequestStatus.bypassed,
  RequestStatus.passed,
];

class FloatingLogNewRowsPill extends StatelessWidget {
  const FloatingLogNewRowsPill({
    super.key,
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 40,
      child: Center(
        child: Material(
          color: colorScheme.primary,
          shape: AppShape.standard,
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  GlyphIcon(
                    AppGlyphs.arrowUp,
                    size: 14,
                    color: colorScheme.onPrimary,
                  ),
                  Text(
                    context.l10n.floatingLogNewRows(count),
                    style: AppTextRole.badge
                        .of(context)
                        .copyWith(color: colorScheme.onPrimary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FloatingLogToast extends StatelessWidget {
  const FloatingLogToast({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 40,
      child: IgnorePointer(
        child: Center(
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: colorScheme.inverseSurface,
              shape: AppShape.standard,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Text(
                message,
                style: AppTextRole.supportingText
                    .of(context)
                    .copyWith(color: colorScheme.onInverseSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FloatingLogEmptyState extends StatelessWidget {
  const FloatingLogEmptyState({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            GlyphIcon(AppGlyphs.requests, size: 28, color: colorScheme.outline),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextRole.bodyStrong
                  .of(context)
                  .copyWith(color: colorScheme.onSurface),
            ),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppTextRole.supportingText
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
