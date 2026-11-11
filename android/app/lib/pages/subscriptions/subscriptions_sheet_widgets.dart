part of 'subscriptions_page.dart';

/// A titled card in the add sheet: header, one card, then an optional footer note.
///
/// The card carries no padding of its own. A pressed row has to reach the card's edge, or its
/// highlight stops short of it as a square rectangle inside the card's rounded shape, so rows
/// take the inset themselves ([ListItem.padding]) and the card's other content does the same
/// ([_SheetField], [_PreviewBox], the notices).
class _SheetCard extends StatelessWidget {
  const _SheetCard({required this.title, required this.children, this.footer});

  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final footer = this.footer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListHeader(title: title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CommonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        if (footer != null) ListFooter(text: footer),
      ],
    );
  }
}

/// Label above a field; `FilledInputTheme` turns floating labels off, so this label lives outside.
class _SheetField extends StatelessWidget {
  const _SheetField({required this.label, required this.child, this.hint});

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final hint = this.hint;
    // The card has no padding (see [_SheetCard]), so a field brings its own.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Text(label, style: context.listCaptionStyle),
          child,
          if (hint != null) Text(hint, style: context.listCaptionStyle),
        ],
      ),
    );
  }
}

/// The address a mirror template would request, in the field's own inset fill.
class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: ShapeDecoration(
          color: context.raisedSurfaceLevel.colorOf(context.colorScheme),
          shape: AppShape.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 2,
          children: [
            Text(
              context.l10n.subsEffectiveUrl,
              style: context.listCaptionStyle,
            ),
            Text(
              url,
              style: context.listCaptionStyle.copyWith(
                color: context.colorScheme.onSurface,
                fontFeatures: appTabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
