// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
part of 'list.dart';

/// A card with arbitrary content that participates in a list group.
///
/// Place it under an [ItemPositionProvider] (for example with
/// [generateGroup]) to round only the outer corners of the group and paint a
/// hairline separator between neighbours. Unlike [DecorationListItem] the
/// content layout is fully caller-defined.
class GroupedCardItem extends StatefulWidget {
  const GroupedCardItem({
    super.key,
    required this.child,
    this.padding,
    this.isSelected = false,
    this.invalid = false,
    this.onPressed,
    this.separatorStartIndent = 16,
    this.separatorEndIndent = 14,
  });

  final Widget child;
  final EdgeInsets? padding;
  final bool isSelected;
  final bool invalid;
  final VoidCallback? onPressed;
  final double separatorStartIndent;
  final double separatorEndIndent;

  @override
  State<GroupedCardItem> createState() => _GroupedCardItemState();
}

class _GroupedCardItemState extends State<GroupedCardItem> {
  final _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position =
        ItemPositionProvider.of(context)?.position ?? ItemPosition.startAndEnd;
    final isStart = [
      ItemPosition.start,
      ItemPosition.startAndEnd,
    ].contains(position);
    final isEnd = [
      ItemPosition.end,
      ItemPosition.startAndEnd,
    ].contains(position);
    final radius = AppRadius.vertical(
      top: isStart ? AppCorner.standard : AppCorner.none,
      bottom: isEnd ? AppCorner.standard : AppCorner.none,
    );
    return _ListRowSeparator(
      separated: !isEnd,
      emphasized: widget.invalid,
      states: _states,
      startIndent: widget.separatorStartIndent,
      endIndent: widget.separatorEndIndent,
      child: CommonCard(
        shape: AppShape.of(radius),
        isError: widget.invalid,
        isSelected: widget.isSelected,
        padding: widget.padding,
        statesController: _states,
        onPressed: widget.onPressed,
        child: widget.child,
      ),
    );
  }
}
