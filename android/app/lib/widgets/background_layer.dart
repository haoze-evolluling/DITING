/// App-wide background layer: a wallpaper under the whole UI plus the same scrim upstream used
/// (0.34 dark, 0.16 light). The path comes from the native cache (`BackgroundBridge.resolve`) and
/// is resolved once per URI; re-resolving on rebuild makes the wallpaper flicker.
library;

import 'dart:io';

import 'package:diting_shared/state/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class AppBackgroundLayer extends ConsumerStatefulWidget {
  const AppBackgroundLayer({super.key, required this.uri, required this.child});

  /// Original wallpaper URI, exchanged for a local cache path natively.
  final String uri;
  final Widget child;

  @override
  ConsumerState<AppBackgroundLayer> createState() => _AppBackgroundLayerState();
}

class _AppBackgroundLayerState extends ConsumerState<AppBackgroundLayer> {
  late Future<String?> _path;

  @override
  void initState() {
    super.initState();
    _path = _resolve();
  }

  @override
  void didUpdateWidget(AppBackgroundLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) _path = _resolve();
  }

  Future<String?> _resolve() =>
      ref.read(backgroundBridgeProvider).resolve(widget.uri);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        FutureBuilder<String?>(
          future: _path,
          builder: (context, snapshot) {
            final path = snapshot.data;
            if (path == null) return const SizedBox.shrink();
            return Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            );
          },
        ),
        // Scrim keeps text legible on bright wallpapers.
        ColoredBox(color: Colors.black.withValues(alpha: dark ? 0.34 : 0.16)),
        widget.child,
      ],
    );
  }
}
