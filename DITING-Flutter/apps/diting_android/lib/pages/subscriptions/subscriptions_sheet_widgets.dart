part of 'subscriptions_page.dart';

/// A titled card in the add sheet: header, one grouped card, then an optional footer note.
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 14,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Text(label, style: context.listCaptionStyle),
        child,
        if (hint != null) Text(hint, style: context.listCaptionStyle),
      ],
    );
  }
}

/// The address a mirror template would request, in the field's own inset fill.
class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(context.colorScheme),
        shape: AppShape.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 2,
        children: [
          Text(context.l10n.subsEffectiveUrl, style: context.listCaptionStyle),
          Text(
            url,
            style: context.listCaptionStyle.copyWith(
              color: context.colorScheme.onSurface,
              fontFamily: appMonospaceFontFamily,
            ),
          ),
        ],
      ),
    );
  }
}
