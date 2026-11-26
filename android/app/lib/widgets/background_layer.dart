library;

import 'dart:io';

import 'package:diting_android/state/settings_providers.dart';
import 'package:diting_android/ui/page_background.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class AppBackgroundLayer extends ConsumerStatefulWidget {
  const AppBackgroundLayer({super.key, required this.uri, required this.child});

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
    return FutureBuilder<String?>(
      future: _path,
      builder: (context, snapshot) {
        final path = snapshot.data;
        return PageBackgroundScope(
          path: path,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (path != null)
                RepaintBoundary(
                  child: Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ColoredBox(
                color: Colors.black.withValues(alpha: dark ? 0.34 : 0.16),
              ),
              widget.child,
            ],
          ),
        );
      },
    );
  }
}
