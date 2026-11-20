import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:material_ui/material_ui.dart';

class SliverPageBody extends StatelessWidget {
  const SliverPageBody({
    super.key,
    required this.slivers,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> slivers;

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

List<Widget> lazySectionSlivers({
  String? title,
  List<IconButtonData> actions = const [],
  required int itemCount,
  required NullableIndexedWidgetBuilder itemBuilder,
  String? footer,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 16),
  double? itemExtent,
  double estimatedItemExtent = SliverPrismList.defaultEstimatedItemExtent,
}) {
  return [
    if (itemCount > 0 && title != null)
      SliverToBoxAdapter(
        child: ListHeader(title: title, actions: actions),
      ),
    SliverPadding(
      padding: padding,
      sliver: SliverPrismList(
        itemCount: itemCount,
        itemExtent: itemExtent,
        estimatedItemExtent: estimatedItemExtent,
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

List<Widget> lazySectionOrEmpty({
  String? title,
  List<IconButtonData> actions = const [],
  required int itemCount,
  required NullableIndexedWidgetBuilder itemBuilder,
  String? footer,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 16),
  double? itemExtent,
  double estimatedItemExtent = SliverPrismList.defaultEstimatedItemExtent,
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
    itemExtent: itemExtent,
    estimatedItemExtent: estimatedItemExtent,
  );
}
