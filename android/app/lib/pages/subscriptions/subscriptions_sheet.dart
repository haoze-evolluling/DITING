part of 'subscriptions_page.dart';

class _AddSubscriptionSheet extends ConsumerStatefulWidget {
  const _AddSubscriptionSheet({this.initial, this.prefillUrl});

  final SubscriptionEntry? initial;

  final String? prefillUrl;

  @override
  ConsumerState<_AddSubscriptionSheet> createState() =>
      _AddSubscriptionSheetState();
}

class _AddSubscriptionSheetState extends ConsumerState<_AddSubscriptionSheet> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  var _kind = SubscriptionKind.domain;

  var _sourceType = SubscriptionSourceType.remote;
  var _picking = false;
  String? _localUri;
  String? _localName;

  String? _formError;
  String? _localWarning;
  int? _groupId;

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
    } else if (widget.prefillUrl case final url?) {
      _url.text = url;
      _sourceType = SubscriptionSourceType.remote;
      if (_name.text.trim().isEmpty) _name.text = extractNameFromUrl(url);
    }
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
      if (_name.text.trim().isEmpty) {
        _name.text = name.substring(0, name.length - 4);
      }
      if (!picked.persisted) {
        _localWarning = context.l10n.subsNoPersistPermission;
      }
    });
  }

  Future<void> _createGroup() async {
    final name = await _askGroupName(
      context,
      title: context.l10n.subsNewGroupTitle,
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
        showAppSnack(
          context,
          message,
          duration: const Duration(milliseconds: 2600),
        );
      case AddSubscriptionOk(:final id):
        final updated = ref.read(subscriptionUpdateProvider.notifier);
        Navigator.of(context).pop();
        await updated.updateOne(
          id,
          confirmLarge: (_, byteLength) =>
              _confirmLargeSubscription(null, byteLength),
        );
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
        showAppSnack(
          context,
          message,
          duration: const Duration(milliseconds: 2600),
        );
      case EditSubscriptionOk(:final needsReimport):
        final updater = ref.read(subscriptionUpdateProvider.notifier);
        Navigator.of(context).pop();
        if (needsReimport) {
          await updater.updateOne(
            entry.id,
            confirmLarge: (_, byteLength) =>
                _confirmLargeSubscription(null, byteLength),
          );
        }
    }
  }

  MirrorTemplateRecord? _selectedTemplate(
    List<MirrorTemplateRecord> templates,
  ) => templates.where((row) => row.template == _mirrorTemplate).firstOrNull;

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
    final String infoHint;
    if (isLocal) {
      infoHint = context.l10n.subsEditLocalHint;
    } else if (isEdit) {
      infoHint = context.l10n.subsEditRemoteHint;
    } else {
      infoHint = context.l10n.subsAddRemoteHint;
    }

    return CommonScaffold(
      title: isEdit ? context.l10n.subsEdit : context.l10n.subsAdd,
      isLoading: _submitting,
      confirmationAction: IconButtonData(
        glyph: TablerIcons.check,
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
            footer: infoHint,
            children: [
              if (!isEdit)
                ListItem<SubscriptionSourceType>.options(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  title: Text(context.l10n.subsSourceType),
                  subtitle: Text(
                    isLocal
                        ? context.l10n.subsSourceLocalPick
                        : context.l10n.subsSourceRemoteDownload,
                  ),
                  options: SubscriptionSourceType.values,
                  value: _sourceType,
                  textBuilder: (type) => type.label(context.l10n),
                  onChanged: (type) => setState(() {
                    _sourceType = type;
                    _formError = null;
                    _localWarning = null;
                  }),
                ),
              if (isLocal) ...[
                if (isEdit)
                  ListItem(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: const Icon(TablerIcons.file_import, size: 20),
                    title: Text(_localName ?? context.l10n.subsLocalRuleFile),
                    subtitle: Text(context.l10n.subsLocalFileSubscription),
                  )
                else
                  ListItem(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: const Icon(TablerIcons.file_import, size: 20),
                    title: Text(_localName ?? context.l10n.subsPickFile),
                    subtitle: Text(
                      _localName == null
                          ? context.l10n.subsLocalFileHint
                          : context.l10n.subsLocalFileRepick,
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
                _SheetField(
                  label: context.l10n.subsNameOptional,
                  child: _nameField(context.l10n.subsNameEmptyFileName),
                ),
              ] else ...[
                _SheetField(
                  label: context.l10n.subsUrl,
                  child: FilledInputTheme(
                    borderRadius: AppRadius.standard,
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
                      style: AppTextRole.rowTitle
                          .of(context)
                          .copyWith(fontFeatures: appTabularFigures),
                      decoration: const InputDecoration(
                        hintText: 'https://example.com/rules.txt',
                      ),
                    ),
                  ),
                ),
                _SheetField(
                  label: context.l10n.subsNameOptional,
                  child: _nameField(context.l10n.subsNameEmptyUrlTail),
                ),
              ],
              if (_formError case final message?)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: InlineNotice(
                    message: message,
                    glyph: TablerIcons.alert_circle,
                    color: context.colorScheme.errorContainer,
                    foregroundColor: context.colorScheme.onErrorContainer,
                  ),
                ),
              if (_localWarning case final warning?)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: InlineNotice(message: warning),
                ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
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
      borderRadius: AppRadius.standard,
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
    if (templates.isEmpty) {
      return _SheetCard(
        title: context.l10n.subsMirrorTitle,
        footer: context.l10n.subsMirrorTemplateFooter,
        children: [
          ListItem(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const Icon(TablerIcons.flip_horizontal, size: 20),
            title: Text(context.l10n.subsAddMirrorTemplate),
            subtitle: Text(context.l10n.subsAddMirrorTemplateSubtitle),
            trailing: const Icon(TablerIcons.chevron_right, size: 18),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: const Icon(TablerIcons.flip_horizontal, size: 20),
          title: Text(context.l10n.subsUseMirrorTemplate),
          subtitle: Text(context.l10n.subsUseMirrorTemplateSubtitle),
          value: _useMirror,
          onChanged: (value) => setState(() {
            _useMirror = value;
            if (value && _mirrorTemplate == null) {
              _mirrorTemplate = templates.firstOrNull?.template;
            }
          }),
        ),
        if (_useMirror) ...[
          ListItem<MirrorTemplateRecord>.options(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text(context.l10n.subsMirrorTemplate),
            subtitle: selected == null
                ? null
                : Text(
                    selected.template,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextRole.supportingText
                        .of(context)
                        .copyWith(fontFeatures: appTabularFigures),
                  ),
            options: templates,
            value: selected ?? templates.first,
            textBuilder: (row) => row.name,
            onChanged: (row) => setState(() => _mirrorTemplate = row.template),
          ),
          if (preview != null) _PreviewBox(url: preview),
          ListItem.toggle(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const Icon(TablerIcons.arrows_exchange, size: 20),
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
