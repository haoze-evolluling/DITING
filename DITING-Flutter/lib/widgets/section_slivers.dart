import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:material_ui/material_ui.dart';

/// Scroll body built from slivers: same app-bar inset, dock clearance and floating-bar scope as
/// [PageBody], but sections added through [lazySectionSlivers] stay lazy.
///
/// `PageBody` takes a `List<Widget>`, so anything built inside it is constructed before the first
/// frame no matter how far below the viewport it sits. A table with six figures of rows inflated
/// all of them in one frame and froze the UI (2026-10-27 ANR, 191,090 rules), so bulk lists use
/// this instead.
class SliverPageBody extends StatelessWidget {
  const SliverPageBody({
    super.key,
    required this.slivers,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> slivers;

  /// Outer padding. Prefer padding on the individual slivers: an outer padding would also inset
  /// the scrollbar and the app-bar background.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: FloatingBarScope(
        inset: 0,
        child: RouteArrivalScope(
          builder: (_, cacheExtent) => CustomScrollView(
            scrollCacheExtent: cacheExtent,
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: context.appBarInset)),
              ...slivers,
              const SliverToBoxAdapter(child: DockSpacer()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header, lazily built rows and an optional footer: the sliver twin of [generateSection].
///
/// Rows are produced on demand, so a section with a hundred thousand entries costs the same first
/// frame as one with ten. Keep-alives are off on purpose: rows are cheap to rebuild, and holding
/// thousands of them alive is what made long lists stutter on the way back up.
List<Widget> lazySectionSlivers({
  String? title,
  List<IconButtonData> actions = const [],
  required int itemCount,
  required NullableIndexedWidgetBuilder itemBuilder,
  String? footer,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 16),
}) {
  return [
    if (itemCount > 0 && title != null)
      SliverToBoxAdapter(
        child: ListHeader(title: title, actions: actions),
      ),
    SliverPadding(
      padding: padding,
      sliver: SliverList.builder(
        itemCount: itemCount,
        addAutomaticKeepAlives: false,
        itemBuilder: (context, index) => ItemPositionProvider(
          position: ItemPosition.get(index, itemCount),
          child: itemBuilder(context, index)!,
        ),
      ),
    ),
    if (itemCount > 0 && footer != null)
      SliverToBoxAdapter(child: ListFooter(text: footer)),
  ];
}

/// [lazySectionSlivers] for the common single-section page, with an empty state in place of the
/// header/footer when there is nothing to show.
List<Widget> lazySectionOrEmpty({
  String? title,
  List<IconButtonData> actions = const [],
  required int itemCount,
  required NullableIndexedWidgetBuilder itemBuilder,
  String? footer,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 16),
  required Widget empty,
}) {
  if (itemCount == 0) return [SliverToBoxAdapter(child: empty)];
  return lazySectionSlivers(
    title: title,
    actions: actions,
    itemCount: itemCount,
    itemBuilder: itemBuilder,
    footer: footer,
    padding: padding,
  );
}
