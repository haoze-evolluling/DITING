/// Small, shared pieces of the cache page: policy names, entry states and the two shapes the
/// console repeats (a labelled switch and a thin fill bar). Nothing here decides cache state; the
/// service does.
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

/// The one write path the cache policy cards share: post the whole config, then say what the service
/// answered. A rejection is reported with the service's reason, because it clamps the numbers and the
/// card must not pretend the value on screen was applied.
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

/// A title, an explanation and a switch: the console's repeated row shape. The switch carries the
/// whole row's tap so a narrow window does not need a pixel-perfect hit on the track.
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

/// A thin fill bar: the hit rate and the capacity are both "part of a whole", and a bar reads
/// faster than a second figure. The value is clamped, so a shrunk limit cannot overdraw.
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
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: ShapeDecoration(
                color: colors.tone,
                shape: AppShape.all(AppCorner.xs),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(
                width: constraints.maxWidth * fill,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: color ?? colorScheme.primary,
                    shape: AppShape.all(AppCorner.xs),
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
