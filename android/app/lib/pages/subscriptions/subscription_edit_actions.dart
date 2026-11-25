part of 'subscription_edit_page.dart';

extension _SubscriptionEditActions on _SubscriptionEditPageState {
  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    if (_isEdit) {
      await _submitEdit();
      return;
    }
    switch (_method) {
      case SubscriptionAddMethod.otherMode:
        await _submitImport();
      case SubscriptionAddMethod.remote:
      case SubscriptionAddMethod.local:
        await _submitAdd();
    }
  }

  Future<void> _submitAdd() async {
    final isLocal = _method == SubscriptionAddMethod.local;
    final error = isLocal
        ? (_localUri == null ? context.l10n.subsPickRuleFile : null)
        : validateSubscriptionUrl(_url.text);
    if (error != null) {
      _updateState(() => _formError = error);
      return;
    }
    _updateState(() {
      _submitting = true;
      _formError = null;
    });
    final result = await ref
        .read(subscriptionActionsProvider)
        .add(
          name: _name.text,
          url: isLocal ? (_localUri ?? '') : _url.text,
          kind: _kind,
          groupId: _groupId,
          mirrorTemplate: isLocal || !_useMirror ? null : _mirrorTemplate,
          mirrorFallback: _mirrorFallback,
          sourceType: isLocal
              ? SubscriptionSourceType.local
              : SubscriptionSourceType.remote,
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case AddSubscriptionFailure(:final message):
        _updateState(() => _submitting = false);
        showAppSnack(
          context,
          message,
          duration: const Duration(milliseconds: 2600),
        );
      case AddSubscriptionOk(:final id):
        final updater = ref.read(subscriptionUpdateProvider.notifier);
        Navigator.of(context).pop();
        await updater.updateOne(
          id,
          confirmLarge: (_, byteLength) =>
              confirmLargeSubscription(null, byteLength),
        );
    }
  }

  Future<void> _submitEdit() async {
    final entryId = widget.subscriptionId;
    if (entryId == null) {
      return;
    }
    final isLocal = _sourceType == SubscriptionSourceType.local;
    _updateState(() {
      _submitting = true;
      _formError = null;
    });
    final result = await ref
        .read(subscriptionActionsProvider)
        .edit(
          entryId,
          name: _name.text,
          url: isLocal ? (_localUri ?? '') : _url.text,
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
        _updateState(() => _submitting = false);
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
            entryId,
            confirmLarge: (_, byteLength) =>
                confirmLargeSubscription(null, byteLength),
          );
        }
    }
  }

  Future<void> _submitImport() async {
    final all = await ref.read(otherModeSubscriptionsProvider.future);
    final current = await ref.read(subscriptionEntriesProvider.future);
    if (!mounted) {
      return;
    }
    final currentKeys = {
      for (final entry in current) subscriptionEntryKey(entry.record),
    };
    final chosen = [
      for (final entry in all)
        if (_selectedKeys.contains(subscriptionEntryKey(entry.record)) &&
            !currentKeys.contains(subscriptionEntryKey(entry.record)))
          entry,
    ];
    if (chosen.isEmpty) {
      _updateState(() => _formError = context.l10n.subsOtherModeNoneSelected);
      return;
    }
    _updateState(() {
      _submitting = true;
      _formError = null;
    });
    final ModeImportResult result;
    try {
      result = await ref
          .read(subscriptionModeImporterProvider)
          .importEntries(chosen);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _updateState(() {
        _submitting = false;
        _formError = error.toString();
      });
      return;
    }
    if (!mounted) {
      return;
    }
    final updater = ref.read(subscriptionUpdateProvider.notifier);
    showAppSnack(
      context,
      context.l10n.subsOtherModeImported(result.ids.length),
      duration: const Duration(milliseconds: 2400),
    );
    Navigator.of(context).pop();
    if (result.ids.isNotEmpty) {
      await updater.updateIds(
        result.ids,
        confirmLarge: (_, byteLength) =>
            confirmLargeSubscription(null, byteLength),
      );
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

  String _infoHint(bool isLocal) {
    if (isLocal) {
      return context.l10n.subsEditLocalHint;
    }
    return _isEdit
        ? context.l10n.subsEditRemoteHint
        : context.l10n.subsAddRemoteHint;
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
          onChanged: (value) => _updateState(() {
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
            onChanged: (row) =>
                _updateState(() => _mirrorTemplate = row.template),
          ),
          if (preview != null) _PreviewBox(url: preview),
          ListItem.toggle(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const Icon(TablerIcons.arrows_exchange, size: 20),
            title: Text(context.l10n.subsMirrorFallback),
            subtitle: Text(context.l10n.subsMirrorFallbackSubtitle),
            value: _mirrorFallback,
            onChanged: (value) => _updateState(() => _mirrorFallback = value),
          ),
        ],
      ],
    );
  }
}
