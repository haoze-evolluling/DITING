// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

typedef WidthWidgetBuilder = Widget Function(
  BuildContext context,
  double width,
);

class WidthBuilder extends StatefulWidget {
  final WidthWidgetBuilder builder;

  const WidthBuilder({super.key, required this.builder});

  @override
  State<WidthBuilder> createState() => _WidthBuilderState();
}

class _WidthBuilderState extends State<WidthBuilder> {
  _WidthBuilt? _built;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final width = constraints.maxWidth;
        final built = _built;
        if (built != null &&
            built.width == width &&
            identical(built.builder, widget.builder)) {
          return built;
        }
        return _built = _WidthBuilt(width: width, builder: widget.builder);
      },
    );
  }
}

class _WidthBuilt extends StatelessWidget {
  final double width;
  final WidthWidgetBuilder builder;

  const _WidthBuilt({required this.width, required this.builder});

  @override
  Widget build(BuildContext context) => builder(context, width);
}

class MemoBuilder extends StatefulWidget {
  final List<Object?> inputs;
  final WidgetBuilder builder;

  const MemoBuilder({super.key, required this.inputs, required this.builder});

  @override
  State<MemoBuilder> createState() => _MemoBuilderState();
}

class _MemoBuilderState extends State<MemoBuilder> {
  Widget? _built;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _built = null;
  }

  @override
  void didUpdateWidget(MemoBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.inputs, widget.inputs)) {
      _built = null;
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    _built = null;
  }

  @override
  Widget build(BuildContext context) => _built ??= widget.builder(context);
}
