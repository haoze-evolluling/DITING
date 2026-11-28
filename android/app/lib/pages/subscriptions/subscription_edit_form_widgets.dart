part of 'subscription_edit_page.dart';

String _modeLabel(DataSet dataSet, AppL10n l10n) => switch (dataSet) {
  DataSet.normal => l10n.workModeNormalTitle,
  DataSet.express => l10n.workModeExpressTitle,
  DataSet.server => l10n.workModeServerTitle,
};

class _MethodPicker extends StatelessWidget {
  const _MethodPicker({required this.value, required this.onChanged});

  final SubscriptionAddMethod value;
  final ValueChanged<SubscriptionAddMethod> onChanged;

  String _hint(AppL10n l10n) => switch (value) {
    SubscriptionAddMethod.remote => l10n.subsSourceRemoteDownload,
    SubscriptionAddMethod.local => l10n.subsSourceLocalPick,
    SubscriptionAddMethod.otherMode => l10n.subsSourceOtherModePick,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        SegmentedControl<SubscriptionAddMethod>(
          segments: [
            (SubscriptionAddMethod.remote, context.l10n.subsMethodRemote),
            (SubscriptionAddMethod.local, context.l10n.subsMethodLocal),
            (SubscriptionAddMethod.otherMode, context.l10n.subsMethodOtherMode),
          ],
          value: value,
          onChanged: onChanged,
        ),
        Text(
          _hint(context.l10n),
          style: AppTextRole.supportingText.of(context),
        ),
      ],
    );
  }
}

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

class _SheetField extends StatelessWidget {
  const _SheetField({required this.label, required this.child, this.hint});

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final hint = this.hint;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Text(label, style: AppTextRole.supportingText.of(context)),
          child,
          if (hint != null)
            Text(hint, style: AppTextRole.supportingText.of(context)),
        ],
      ),
    );
  }
}

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
          shape: AppShape.standard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 2,
          children: [
            Text(
              context.l10n.subsEffectiveUrl,
              style: AppTextRole.supportingText.of(context),
            ),
            Text(
              url,
              style: AppTextRole.supportingText
                  .of(context)
                  .copyWith(
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
