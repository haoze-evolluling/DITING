part of 'subscriptions_page.dart';

/// Add/edit-subscription sheet. Grouped cards rather than a label column: the two fields need the full
/// width, and the mirror templates the legacy app offered were missing here. Saving inserts with
/// `importState = importing`, then a real download settles it. With [initial] the sheet edits that
/// row instead; the source type and a local row's file stay fixed.
class _AddSubscriptionSheet extends ConsumerStatefulWidget {
  const _AddSubscriptionSheet({this.initial});

  final SubscriptionEntry? initial;

  @override
  ConsumerState<_AddSubscriptionSheet> createState() =>
      _AddSubscriptionSheetState();
}

class _AddSubscriptionSheetState extends ConsumerState<_AddSubscriptionSheet> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  var _kind = SubscriptionKind.domain;

  /// Remote subscriptions download a URL; local ones import a picked `.txt` through a
  /// persisted SAF grant, so the address field is replaced by a file row.
  var _sourceType = SubscriptionSourceType.remote;
  var _picking = false;
  String? _localUri;
  String? _localName;

  /// Blocks submission; `_localWarning` only warns about a grant that will not survive.
  String? _formError;
  String? _localWarning;
  int? _groupId;

  /// Mirror acceleration, as the legacy form: a switch, one saved template and fallback.
  var _useMirror = false;
  String? _mirrorTemplate;
  var _mirrorFallback = true;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial case final entry?) {
      final record = entry.record;
      _name.text = record.name;
      _kind = record.kind;
      _groupId = record.groupId;
      _sourceType = record.sourceType;
      _mirrorFallback = record.mirrorFallback;
      if (record.isRemote) {
        _url.text = record.url;
        _mirrorTemplate = record.mirrorTemplate;
        _useMirror = record.mirrorTemplate != null;
      } else {
        _localUri = record.url;
        _localName = _SubscriptionCard._fileNameOf(record.url);
      }
    }
    // The mirror preview follows the address while it is typed.
    _url.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _url.removeListener(_rebuild);
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    if (_picking) {
      return;
    }
    setState(() {
      _picking = true;
      _formError = null;
      _localWarning = null;
    });
    final picked = await ref
        .read(subscriptionFileReaderProvider)
        .pickPersistableTextFile();
    if (!mounted) {
      return;
    }
    setState(() {
      _picking = false;
      if (picked.cancelled) {
        return;
      }
      if (picked.error != null) {
        _formError = picked.error;
        return;
      }
      final name = picked.displayName;
      if (!name.toLowerCase().endsWith('.txt')) {
        _formError = context.l10n.subsPickTxt;
        return;
      }
      _localUri = picked.uri;
      _localName = name;
      // Prefill the name so the row is identifiable without typing.
      if (_name.text.trim().isEmpty) {
        _name.text = name.substring(0, name.length - 4);
      }
      if (!picked.persisted) {
        _localWarning = context.l10n.subsNoPersistPermission;
      }
    });
  }

  Future<void> _createGroup() async {
    final name = await showFloatingDialog<String>(
      context: context,
      child: InputDialog(
        title: context.l10n.subsNewGroupTitle,
        value: '',
        validator: (value) => (value ?? '').trim().isEmpty ? context.l10n.subsGroupNameRequired : null,
      ),
    );
    if (name == null || !mounted) {
      return;
    }
    final id = await ref.read(subscriptionActionsProvider).createGroup(name);
    if (id == null || !mounted) {
      return;
    }
    setState(() => _groupId = id);
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    final isLocal = _sourceType == SubscriptionSourceType.local;
    final error = isLocal
        ? (_localUri == null ? context.l10n.subsPickRuleFile : null)
        : validateSubscriptionUrl(_url.text);
    if (error != null) {
      setState(() => _formError = error);
      return;
    }
    setState(() {
      _submitting = true;
      _formError = null;
    });
    if (widget.initial case final entry?) {
      await _submitEdit(entry, isLocal);
      return;
    }
    final result = await ref
        .read(subscriptionActionsProvider)
        .add(
          name: _name.text,
          url: isLocal ? (_localUri ?? '') : _url.text,
          kind: _kind,
          groupId: _groupId,
          mirrorTemplate: isLocal || !_useMirror ? null : _mirrorTemplate,
          mirrorFallback: _mirrorFallback,
          sourceType: _sourceType,
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case AddSubscriptionFailure(:final message):
        setState(() => _submitting = false);
        // A duplicate address keeps the sheet open so the pasted text stays editable.
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 2600),
          ),
        );
      case AddSubscriptionOk(:final id):
        // Start the download before closing so the list spins as the sheet disappears.
        final updated = ref.read(subscriptionUpdateProvider.notifier);
        Navigator.of(context).pop();
        await updated.updateOne(id);
    }
  }

  Future<void> _submitEdit(SubscriptionEntry entry, bool isLocal) async {
    final result = await ref
        .read(subscriptionActionsProvider)
        .edit(
          entry.id,
          name: _name.text,
          url: _url.text,
          kind: _kind,
          groupId: _groupId,
          mirrorTemplate: isLocal || !_useMirror ? null : _mirrorTemplate,
          mirrorFallback: _mirrorFallback,
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case EditSubscriptionFailure(:final message):
        setState(() => _submitting = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 2600),
          ),
        );
      case EditSubscriptionOk(:final needsReimport):
        final updater = ref.read(subscriptionUpdateProvider.notifier);
        Navigator.of(context).pop();
        // The stored rules came from the old address or kind, so replace them now.
        if (needsReimport) {
          await updater.updateOne(entry.id);
        }
    }
  }

  /// The saved template [record] points at, if it is still in the list.
  MirrorTemplateRecord? _selectedTemplate(
    List<MirrorTemplateRecord> templates,
  ) => templates.where((row) => row.template == _mirrorTemplate).firstOrNull;

  /// What the mirror would request, or null while the address is empty or malformed.
  String? _mirrorPreview(MirrorTemplateRecord? template) {
    final address = _url.text.trim();
    if (template == null || address.isEmpty) {
      return null;
    }
    try {
      return buildMirrorUrl(template.template, address);
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(subscriptionGroupsProvider).value ?? const [];
    final templates =
        ref.watch(mirrorTemplatesProvider).value ??
        const <MirrorTemplateRecord>[];
    final selectedGroup = groups.any((group) => group.id == _groupId)
        ? _groupId
        : null;
    final isLocal = _sourceType == SubscriptionSourceType.local;
    final isEdit = widget.initial != null;
    final template = _selectedTemplate(templates);

    return CommonScaffold(
      title: isEdit ? context.l10n.subsEdit : context.l10n.subsAdd,
      isLoading: _submitting,
      confirmationAction: IconButtonData(
        glyph: AppGlyphs.check,
        tooltip: context.l10n.subsSaveTooltip,
        onPressed: _submitting ? null : _submit,
      ),
      body: ListView(
        controller: sheetScrollController(context),
        padding: EdgeInsets.only(
          top: 8 + context.contentTopPadding,
          bottom: 24,
        ),
        children: [
          _SheetCard(
            title: context.l10n.subsInfoSection,
            footer: isEdit
                ? context.l10n.subsEditRemoteHint
                : isLocal
                ? context.l10n.subsEditLocalHint
                : context.l10n.subsAddRemoteHint,
            children: [
              if (isLocal) ...[
                if (isEdit)
                  ListItem(
                    padding: EdgeInsets.zero,
                    leading: const GlyphIcon(AppGlyphs.importFile, size: 20),
                    title: Text(_localName ?? context.l10n.subsLocalRuleFile),
                    subtitle: Text(context.l10n.subsLocalFileSubscription),
                  )
                else
                  ListItem(
                    padding: EdgeInsets.zero,
                    leading: const GlyphIcon(AppGlyphs.importFile, size: 20),
                    title: Text(_localName ?? context.l10n.subsPickFile),
                    subtitle: Text(
                      _localName == null ? context.l10n.subsLocalFileHint : context.l10n.subsLocalFileRepick,
                    ),
                    trailing: TonalButton(
                      size: TonalButtonSize.compact,
                      label: _localName == null
                          ? context.l10n.subsChoose
                          : context.l10n.subsChange,
                      onPressed: _picking ? null : _pickFile,
                    ),
                    onTap: _picking ? null : _pickFile,
                  ),
                _SheetField(label: context.l10n.subsNameOptional, child: _nameField(context.l10n.subsNameEmptyFileName)),
              ] else ...[
                _SheetField(
                  label: context.l10n.subsUrl,
                  child: FilledInputTheme(
                    borderRadius: AppRadius.md,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: TextFormField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(
                        fontFamily: appMonospaceFontFamily,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'https://example.com/rules.txt',
                      ),
                    ),
                  ),
                ),
                _SheetField(label: context.l10n.subsNameOptional, child: _nameField(context.l10n.subsNameEmptyUrlTail)),
              ],
              if (_formError case final message?)
                InlineNotice(
                  message: message,
                  glyph: AppGlyphs.error,
                  color: context.colorScheme.errorContainer,
                  foregroundColor: context.colorScheme.onErrorContainer,
                ),
              if (_localWarning case final warning?)
                InlineNotice(message: warning),
            ],
          ),
          if (!isLocal)
            _mirrorCard(
              templates: templates,
              selected: template,
              preview: _mirrorPreview(template),
            ),
          _SheetCard(
            title: context.l10n.subsRuleType,
            children: [
              ListItem<SubscriptionKind>.options(
                padding: EdgeInsets.zero,
                title: Text(context.l10n.subsKindLabel),
                subtitle: Text(
                  _kind == SubscriptionKind.hosts
                      ? context.l10n.subsKindHostsHint
                      : context.l10n.subsKindDomainHint,
                ),
                options: SubscriptionKind.values,
                value: _kind,
                textBuilder: (kind) => kind.displayName(context.l10n),
                onChanged: (kind) => setState(() => _kind = kind),
              ),
              _SheetField(
                label: context.l10n.subsGroupLabel,
                hint: context.l10n.subsGroupHint,
                child: ChipRow(
                  children: [
                    FilterPill(
                      label: SubscriptionEntry.ungroupedLabel,
                      selected: selectedGroup == null,
                      onPressed: () => setState(() => _groupId = null),
                    ),
                    for (final group in groups)
                      FilterPill(
                        label: group.name,
                        selected: group.id == selectedGroup,
                        onPressed: () => setState(() => _groupId = group.id),
                      ),
                    TonalChip(
                      label: context.l10n.subsNewGroupShort,
                      color: context.raisedSurfaceLevel.colorOf(
                        context.colorScheme,
                      ),
                      foregroundColor: context.colorScheme.onSurfaceVariant,
                      onPressed: _createGroup,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _nameField(String hintText) {
    return FilledInputTheme(
      borderRadius: AppRadius.md,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: TextFormField(
        controller: _name,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: hintText),
      ),
    );
  }

  Widget _mirrorCard({
    required List<MirrorTemplateRecord> templates,
    required MirrorTemplateRecord? selected,
    required String? preview,
  }) {
    // Without a saved template there is nothing to switch on, so the card points at the
    // management page instead of offering a dead toggle.
    if (templates.isEmpty) {
      return _SheetCard(
        title: context.l10n.subsMirrorTitle,
        footer: context.l10n.subsMirrorTemplateFooter,
        children: [
          ListItem(
            padding: EdgeInsets.zero,
            leading: const GlyphIcon(AppGlyphs.layers, size: 20),
            title: Text(context.l10n.subsAddMirrorTemplate),
            subtitle: Text(context.l10n.subsAddMirrorTemplateSubtitle),
            trailing: const GlyphIcon(AppGlyphs.chevronForward, size: 18),
            onTap: () => context.push(HubPaths.mirrorTemplates),
          ),
        ],
      );
    }
    return _SheetCard(
      title: context.l10n.subsMirrorTitle,
      footer: context.l10n.subsMirrorFooter,
      children: [
        ListItem.toggle(
          padding: EdgeInsets.zero,
          leading: const GlyphIcon(AppGlyphs.bolt, size: 20),
          title: Text(context.l10n.subsUseMirrorTemplate),
          subtitle: Text(context.l10n.subsUseMirrorTemplateSubtitle),
          value: _useMirror,
          onChanged: (value) => setState(() {
            _useMirror = value;
            // Enabling with nothing chosen picks the newest template, so saving does not
            // silently drop the mirror the user just turned on.
            if (value && _mirrorTemplate == null) {
              _mirrorTemplate = templates.firstOrNull?.template;
            }
          }),
        ),
        if (_useMirror) ...[
          ListItem<MirrorTemplateRecord>.options(
            padding: EdgeInsets.zero,
            title: Text(context.l10n.subsMirrorTemplate),
            subtitle: selected == null
                ? null
                : Text(
                    selected.template,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.listCaptionStyle.copyWith(
                      fontFamily: appMonospaceFontFamily,
                    ),
                  ),
            options: templates,
            value: selected ?? templates.first,
            textBuilder: (row) => row.name,
            onChanged: (row) => setState(() => _mirrorTemplate = row.template),
          ),
          if (preview != null) _PreviewBox(url: preview),
          ListItem.toggle(
            padding: EdgeInsets.zero,
            leading: const GlyphIcon(AppGlyphs.swap, size: 20),
            title: Text(context.l10n.subsMirrorFallback),
            subtitle: Text(context.l10n.subsMirrorFallbackSubtitle),
            value: _mirrorFallback,
            onChanged: (value) => setState(() => _mirrorFallback = value),
          ),
        ],
      ],
    );
  }
}
