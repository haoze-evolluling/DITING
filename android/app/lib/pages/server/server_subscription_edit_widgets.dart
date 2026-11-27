part of 'server_subscription_edit_page.dart';

class _SheetCard extends StatelessWidget {
  const _SheetCard({required this.title, required this.children, this.footer});

  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
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
        if (footer case final text?) ListFooter(text: text),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.hint});

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Text(label, style: AppTextRole.supportingText.of(context)),
          child,
          if (hint case final text?)
            Text(text, style: AppTextRole.supportingText.of(context)),
        ],
      ),
    );
  }
}

class _TemplateChoice {
  const _TemplateChoice.pick(this.value)
    : add = false,
      delete = null;

  const _TemplateChoice.add()
    : value = null,
      add = true,
      delete = null;

  const _TemplateChoice.delete(String this.delete)
    : value = null,
      add = false;

  final String? value;
  final bool add;
  final String? delete;
}

class _TemplateSheet extends StatelessWidget {
  const _TemplateSheet({required this.templates, required this.selected});

  final List<String> templates;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.l10n.subsMirrorTemplate,
      body: ListView(
        padding: EdgeInsets.only(top: context.contentTopPadding, bottom: 24),
        children: [
          generateSection(
            items: [
              ListItem(
                leading: const Icon(TablerIcons.flip_horizontal, size: 20),
                title: Text(context.l10n.serverSubsMirrorOff),
                trailing: selected == null ? const SelectionCheck() : null,
                onTap: () =>
                    Navigator.of(context).pop(const _TemplateChoice.pick(null)),
              ),
              for (final template in templates)
                ListItem(
                  leading: const Icon(TablerIcons.link, size: 20),
                  title: Text(
                    template,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected == template) const SelectionCheck(),
                      IconButton(
                        tooltip: context.l10n.commonDelete,
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(_TemplateChoice.delete(template)),
                        icon: const Icon(TablerIcons.trash, size: 18),
                      ),
                    ],
                  ),
                  onTap: () => Navigator.of(
                    context,
                  ).pop(_TemplateChoice.pick(template)),
                ),
              ListItem(
                leading: const Icon(TablerIcons.plus, size: 20),
                title: Text(context.l10n.subsAddMirrorTemplate),
                onTap: () =>
                    Navigator.of(context).pop(const _TemplateChoice.add()),
              ),
            ],
            footer: context.l10n.subsMirrorTemplateFooter,
          ),
        ],
      ),
    );
  }
}
