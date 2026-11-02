// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'scaffold.dart';

/// Holds a body whose top stays put clear of the bar floating over it.
class AppBarClearance extends StatelessWidget {
  const AppBarClearance({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: context.appBarInset),
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: FloatingBarScope(inset: 0, child: child),
      ),
    );
  }
}

class _KeywordStrip extends StatelessWidget {
  const _KeywordStrip({required this.keywords, required this.onDeleted});

  final List<String> keywords;
  final ValueChanged<String> onDeleted;

  static const _inset = 16.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TonalButtonSize.section.button,
      child: WidthBuilder(
        builder: (_, width) => ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: _inset),
          itemCount: keywords.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, index) {
            final keyword = keywords[index];
            return ConstrainedBox(
              key: ValueKey(keyword),
              constraints: BoxConstraints(
                maxWidth: math.max(0, width - 2 * _inset),
              ),
              child: CommonChip(
                label: keyword,
                onDeleted: () => onDeleted(keyword),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Keeps rebuilds in the body to its own layer (.agents/architecture.md).
class _BodyScope extends StatelessWidget {
  const _BodyScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _BodyBoundary(child: LayoutBuilder(builder: (_, _) => child));
  }
}

class _BodyBoundary extends SingleChildRenderObjectWidget {
  const _BodyBoundary({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBodyBoundary();
}

class _RenderBodyBoundary extends RenderProxyBox {
  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    child?.layout(constraints);
  }
}

/// Flutter reveals a focused control against the viewport alone, which runs
/// under a floating bar, so keyboard and remote traversal would park it there.
class _FocusClearOfBar extends StatefulWidget {
  const _FocusClearOfBar({required this.inset, required this.child});

  final double inset;
  final Widget child;

  @override
  State<_FocusClearOfBar> createState() => _FocusClearOfBarState();
}

class _FocusClearOfBarState extends State<_FocusClearOfBar> {
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    final manager = FocusManager.instance;
    final focused = manager.primaryFocus?.context;
    if (manager.highlightMode != FocusHighlightMode.traditional ||
        focused == null ||
        focused.findAncestorStateOfType<_FocusClearOfBarState>() != this) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(focused));
  }

  void _reveal(BuildContext focused) {
    if (!mounted || !focused.mounted) {
      return;
    }
    var scrollable = Scrollable.maybeOf(focused);
    while (scrollable != null && scrollable.position.axis != Axis.vertical) {
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    final body = context.findRenderObject();
    final target = focused.findRenderObject();
    final viewport = scrollable?.context.findRenderObject();
    if (scrollable == null ||
        body is! RenderBox ||
        target is! RenderBox ||
        viewport is! RenderBox) {
      return;
    }
    final barBottom = body.localToGlobal(Offset.zero).dy + widget.inset;
    final covered = barBottom - target.localToGlobal(Offset.zero).dy;
    if (covered <= 0 || viewport.localToGlobal(Offset.zero).dy >= barBottom) {
      return;
    }
    final position = scrollable.position;
    final delta = axisDirectionIsReversed(position.axisDirection)
        ? covered
        : -covered;
    position.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
