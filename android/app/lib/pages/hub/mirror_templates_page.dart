// ignore_for_file: sort_child_properties_last

part of 'subscription_tools_pages.dart';

/// Mirror templates (upstream `MirrorTemplateScreen`), stored in the legacy
/// `mirror_template` table through `MirrorTemplateRepository` so they survive a restart.
class MirrorTemplatesPage extends ConsumerWidget {
  const MirrorTemplatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(mirrorTemplatesProvider);
    final rows = templates.value;
    return CommonScaffold(
      title: context.l10n.mirrorTplTitle,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.add,
          tooltip: context.l10n.mirrorTplAdd,
          onPressed: () => _add(context, ref),
        ),
      ],
      body: PageBody(
        children: [
          PageIntroCard(text: context.l10n.mirrorTplIntro),
          if (rows != null) GlobalMirrorSection(templates: rows),
          generateSection(
            title: context.l10n.mirrorTplActions,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.info),
                title: Text(context.l10n.mirrorTplFormatExample),
                subtitle: Text(context.l10n.mirrorTplFormatExampleSubtitle),
                onTap: () => _showFormatGuide(context),
              ),
            ],
          ),
          if (templates.hasError)
            generateSection(
              title: context.l10n.mirrorTplSaved,
              items: [
                ListItem(
                  leading: GlyphIcon(AppGlyphs.error),
                  title: Text(context.l10n.mirrorTplReadFailed),
                  subtitle: Text(context.l10n.mirrorTplReadFailedSubtitle),
                ),
              ],
            )
          else
            generateSection(
              title: context.l10n.mirrorTplSavedCount(rows?.length ?? 0),
              items: [
                for (final row in rows ?? const <MirrorTemplateRecord>[])
                  ListItem(
                    leading: const GlyphIcon(AppGlyphs.layers, size: 20),
                    title: Text(row.name),
                    subtitle: Text(row.template),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: context.l10n.commonEdit,
                          onPressed: () => _edit(context, ref, row),
                          icon: const GlyphIcon(AppGlyphs.edit, size: 20),
                        ),
                        IconButton(
                          tooltip: context.l10n.commonDelete,
                          onPressed: () async {
                            await ref
                                .read(mirrorTemplateActionsProvider)
                                .remove(row.id);
                            ref
                                .read(globalMirrorProvider.notifier)
                                .templateRemoved(row.template);
                          },
                          icon: const GlyphIcon(AppGlyphs.delete, size: 20),
                        ),
                      ],
                    ),
                  ),
              ],
              footer: rows == null
                  ? context.l10n.mirrorTplReading
                  : rows.isEmpty
                  ? context.l10n.mirrorTplEmpty
                  : null,
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final result = await _editTemplate(context);
    if (result == null) return;
    final id = await ref
        .read(mirrorTemplateActionsProvider)
        .create(name: result.name, template: result.template);
    if (id == null && context.mounted) {
      // The unique index on the name rejects the insert; report it instead of silently
      // doing nothing.
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.l10n.mirrorTplDuplicate),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    MirrorTemplateRecord row,
  ) async {
    final result = await _editTemplate(
      context,
      initial: (name: row.name, template: row.template),
    );
    if (result == null) return;
    final ok = await ref
        .read(mirrorTemplateActionsProvider)
        .update(id: row.id, name: result.name, template: result.template);
    if (ok) {
      ref
          .read(globalMirrorProvider.notifier)
          .templateChanged(row.template, result.template);
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.l10n.mirrorTplDuplicateSave),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<({String name, String template})?> _editTemplate(
    BuildContext context, {
    ({String name, String template})? initial,
  }) {
    return showFloatingDialog<({String name, String template})>(
      context: context,
      child: _TemplateDialog(initial: initial),
    );
  }

  void _showFormatGuide(BuildContext context) {
    showFloatingDialog<void>(
      context: context,
      child: CommonDialog(
        title: context.l10n.mirrorTplFormatTitle,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(context.l10n.mirrorTplFormatIntro),
            Text(context.l10n.mirrorTplFormatUrl('{url}')),
            Text(context.l10n.mirrorTplFormatScheme('{scheme}')),
            Text(context.l10n.mirrorTplFormatUrlEncoded('{urlEncoded}')),
            Text(context.l10n.mirrorTplFormatHost('{host}')),
            Text(context.l10n.mirrorTplFormatPath('{path}')),
            Text(context.l10n.mirrorTplFormatPathAndQuery('{pathAndQuery}')),
            Text(context.l10n.mirrorTplFormatSample('{url}')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.uiClose),
          ),
        ],
      ),
    );
  }
}

/// Mirror template editor. The controller is owned by the dialog: disposing it from
/// `whenComplete` fires on `pop` while the `TextField` is still animating out.
class _TemplateDialog extends StatefulWidget {
  const _TemplateDialog({this.initial});

  final ({String name, String template})? initial;

  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  static final _placeholder = RegExp(
    r'\{(url|scheme|urlEncoded|host|path|pathAndQuery)\}',
  );

  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _template = TextEditingController(
    text: widget.initial?.template ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _template.dispose();
    super.dispose();
  }

  bool get _valid =>
      _template.text.startsWith('http') &&
      _placeholder.hasMatch(_template.text);

  void _submit() {
    if (!_valid || _name.text.trim().isEmpty) {
      return;
    }
    Navigator.of(context)
        .pop((name: _name.text.trim(), template: _template.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: widget.initial == null ? context.l10n.mirrorTplAddTitle : context.l10n.mirrorTplEditTitle,
      hasFields: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: context.l10n.mirrorTplNameLabel,
              hintText: context.l10n.mirrorTplNameHint,
            ),
          ),
          TextField(
            controller: _template,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: context.l10n.mirrorTplAddressLabel,
              hintText: 'https://mirror.example.com/{url}',
            ),
          ),
          Text(
            _valid
                ? context.l10n.mirrorTplFormatPlaceholders(
                    '{url}',
                    '{scheme}',
                    '{urlEncoded}',
                    '{host}',
                    '{path}',
                    '{pathAndQuery}',
                  )
                : context.l10n.mirrorTplInvalid,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(
                  color: _valid
                      ? context.colorScheme.onSurfaceVariant
                      : context.colorScheme.error,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.uiCancel),
        ),
        TextButton(
          onPressed: _valid && _name.text.trim().isNotEmpty ? _submit : null,
          child: Text(context.l10n.commonSave),
        ),
      ],
    );
  }
}
