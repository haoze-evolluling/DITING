import 'dart:typed_data';

import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const appIconTileSize = 40.0;

class AppIconAvatar extends ConsumerStatefulWidget {
  const AppIconAvatar({
    super.key,
    required this.packageName,
    this.size = appIconTileSize,
    this.glyph,
  });

  final String packageName;
  final double size;

  final Glyph? glyph;

  @override
  ConsumerState<AppIconAvatar> createState() => _AppIconAvatarState();
}

class _AppIconAvatarState extends ConsumerState<AppIconAvatar> {
  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(AppIconAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageName != widget.packageName) _request();
  }

  void _request() {
    ref.read(appIconsProvider.notifier).request([widget.packageName]);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = ref.watch(
      appIconsProvider.select((icons) => icons[widget.packageName]),
    );
    final size = widget.size;
    final colors = context.colorScheme;
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: AppRadius.standard,
          child: ColoredBox(
            color: colors.surfaceContainerHighest,
            child: bytes == null
                ? Center(
                    child: GlyphIcon(
                      widget.glyph ?? AppGlyphs.appsList,
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
