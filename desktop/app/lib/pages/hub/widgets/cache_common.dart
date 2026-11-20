library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_cache_models.dart';
import 'package:diting_desktop/data/api/desktop_cache_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

Future<void> saveCacheSetting(
  BuildContext context,
  WidgetRef ref,
  DesktopCacheConfig next,
  String success,
) async {
  final l10n = context.l10n;
  final error = await ref
      .read(desktopCacheConfigProvider.notifier)
      .save(next);
  if (!context.mounted) return;
  showDesktopMessage(
    context,
    error == null
        ? success
        : l10n.desktopCacheSaveFailed(error.message),
  );
}

String desktopCacheModeLabel(BuildContext context, String mode) {
  final l10n = context.l10n;
  return switch (mode) {
    'follow_dns_ttl' => l10n.desktopCacheModeFollow,
    'fixed_ttl' => l10n.desktopCacheModeFixed,
    _ => l10n.desktopCacheModeLimit,
  };
}

String desktopCacheStatusLabel(BuildContext context, DesktopCacheEntry entry) {
  final l10n = context.l10n;
  if (entry.isNegative) return l10n.desktopCacheStatusNegative;
  return entry.isStale
      ? l10n.desktopCacheStatusStale
      : l10n.desktopCacheStatusFresh;
}

DashboardChipTone desktopCacheStatusTone(DesktopCacheEntry entry) {
  if (entry.isNegative) return DashboardChipTone.warn;
  return entry.isStale ? DashboardChipTone.warn : DashboardChipTone.ok;
}

String desktopCacheFilterLabel(
  BuildContext context,
  DesktopCacheEntryFilter filter,
) {
  final l10n = context.l10n;
  return switch (filter) {
    DesktopCacheEntryFilter.all => l10n.desktopCacheFilterAll,
    DesktopCacheEntryFilter.fresh => l10n.desktopCacheFilterFresh,
    DesktopCacheEntryFilter.stale => l10n.desktopCacheFilterStale,
    DesktopCacheEntryFilter.negative => l10n.desktopCacheFilterNegative,
  };
}

class CacheToggleRow extends StatelessWidget {
  const CacheToggleRow({
    super.key,
    required this.title,
    required this.body,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String body;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DashboardBlock(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context),
                ),
                Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.label(context),
                ),
              ],
            ),
          ),
          DashboardSwitch(
            value: value,
            semanticLabel: title,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class CacheBar extends StatelessWidget {
  const CacheBar({super.key, required this.value, this.height = 6, this.color});

  final double value;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final fill = value.isNaN ? 0.0 : value.clamp(0, 1).toDouble();
    final shape = AppShape.standard;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: ShapeDecoration(color: colors.track, shape: shape),
          ),
          FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: fill,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: color ?? colorScheme.primary,
                shape: shape,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
