import 'dart:typed_data';

import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// 40 dp tile with a 14 dp corner, matching 1.4.3 `AppIconShape`.
const appIconTileSize = 40.0;
const appIconTileRadius = 14.0;

/// Real launcher icon for one package, cached by [appIconsProvider] so scrolling only ever hits an
/// in-memory map. Packages without an icon fall back to [fallback] on the same tile shape, which
/// keeps row heights identical whether or not the platform answered.
class AppIconAvatar extends ConsumerWidget {
  const AppIconAvatar({
    super.key,
    required this.packageName,
    this.size = appIconTileSize,
    this.glyph,
  });

  final String packageName;
  final double size;

  /// Placeholder glyph; defaults to the app-list glyph used by the legacy screen.
  final Glyph? glyph;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `select`: a batch of icons landing rebuilds only the rows it covers.
    final bytes = ref.watch(
      appIconsProvider.select((icons) => icons[packageName]),
    );
    final colors = context.colorScheme;
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(appIconTileRadius),
          child: ColoredBox(
            color: colors.surfaceContainerHighest,
            child: bytes == null
                ? Center(
                    child: GlyphIcon(
                      glyph ?? AppGlyphs.appsList,
                      size: size * 0.6,
                      color: colors.onSurfaceVariant,
                    ),
                  )
                : _AppIconImage(bytes: bytes, size: size),
          ),
        ),
      ),
    );
  }
}

class _AppIconImage extends StatelessWidget {
  const _AppIconImage({required this.bytes, required this.size});

  final Uint8List bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Decoding at the device pixel ratio keeps a 192 px source from being rasterised larger than
    // the tile ever draws, which is what made long lists drop frames while scrolling.
    final target = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return Image.memory(
      bytes,
      width: size,
      height: size,
      cacheWidth: target.clamp(1, 512),
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) => Center(
        child: GlyphIcon(
          AppGlyphs.appsList,
          size: size * 0.6,
          color: context.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
