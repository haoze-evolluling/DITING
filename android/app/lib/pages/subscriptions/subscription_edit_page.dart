library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/db/mirror_template_repository.dart';
import 'package:diting_android/data/db/subscription_models.dart';
import 'package:diting_android/data/subscriptions/subscription_url.dart';
import 'package:diting_android/pages/subscriptions/subscription_common.dart';
import 'package:diting_android/routes/routes.dart';
import 'package:diting_android/state/subscription_providers.dart';
import 'package:diting_shared/data/db/datasets.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/chip_row.dart';
import 'package:diting_android/widgets/notice.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

part 'subscription_edit_actions.dart';
part 'subscription_edit_form_widgets.dart';
part 'subscription_edit_import_section.dart';

enum SubscriptionAddMethod { remote, local, otherMode }

class SubscriptionEditPage extends ConsumerStatefulWidget {
  const SubscriptionEditPage({super.key, this.subscriptionId, this.prefillUrl});

  /// 编辑已有订阅时传入；为空表示新增。
  final int? subscriptionId;

  /// 深链导入等场景下预填的订阅地址。
  final String? prefillUrl;

  @override
  ConsumerState<SubscriptionEditPage> createState() =>
      _SubscriptionEditPageState();
}

class _SubscriptionEditPageState extends ConsumerState<SubscriptionEditPage> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _selectedKeys = <String>{};

  var _method = SubscriptionAddMethod.remote;
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

  var _loading = false;
  String? _loadError;

  bool get _isEdit => widget.subscriptionId != null;

  void _updateState(VoidCallback change) => setState(change);

  @override
  void initState() {
    super.initState();
    if (widget.prefillUrl case final url?) {
      _url.text = url;
      _name.text = extractNameFromUrl(url);
    }
    if (_isEdit) {
      _loading = true;
      _loadEntry();
    }
  }

  Future<void> _loadEntry() async {
    final id = widget.subscriptionId;
    if (id == null) {
      return;
    }
    final entries = await ref.read(subscriptionEntriesProvider.future);
    if (!mounted) {
      return;
    }
    final entry = entries.where((item) => item.id == id).firstOrNull;
    if (entry == null) {
      setState(() {
        _loading = false;
        _loadError = context.l10n.subscriptionNotFound;
      });
      return;
    }
    _applyEntry(entry);
    setState(() => _loading = false);
  }

  void _applyEntry(SubscriptionEntry entry) {
    final record = entry.record;
    _name.text = record.name;
    _kind = record.kind;
    _groupId = record.groupId;
    _sourceType = record.sourceType;
    _mirrorFallback = record.mirrorFallback;
    if (record.isRemote) {
      _method = SubscriptionAddMethod.remote;
      _url.text = record.url;
      _mirrorTemplate = record.mirrorTemplate;
      _useMirror = record.mirrorTemplate != null;
    } else {
      _method = SubscriptionAddMethod.local;
      _localUri = record.url;
      _localName = subscriptionFileNameOf(record.url);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _changeMethod(SubscriptionAddMethod method) {
    if (method == _method) {
      return;
    }
    setState(() {
      _method = method;
      _formError = null;
      _localWarning = null;
    });
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
    final name = await askSubscriptionGroupName(
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

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? context.l10n.subsEdit : context.l10n.subsAdd;
    if (_loading) {
      return CommonScaffold(
        title: title,
        body: const Center(child: CommonCircleLoading()),
      );
    }
    final loadError = _loadError;
    if (loadError != null) {
      return CommonScaffold(
        title: title,
        body: PageBody(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: InlineNotice(
                message: loadError,
                glyph: TablerIcons.alert_circle,
                color: context.colorScheme.errorContainer,
                foregroundColor: context.colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      );
    }
    final groups =
        ref.watch(subscriptionGroupsProvider).value ??
        const <SubscriptionGroupRecord>[];
    final templates =
        ref.watch(mirrorTemplatesProvider).value ??
        const <MirrorTemplateRecord>[];
    final selectedGroup = groups.any((group) => group.id == _groupId)
        ? _groupId
        : null;
    final isLocal = _isEdit
        ? _sourceType == SubscriptionSourceType.local
        : _method == SubscriptionAddMethod.local;
    final importing = !_isEdit && _method == SubscriptionAddMethod.otherMode;
    final otherMode = importing ? ref.watch(otherModeDataSetProvider) : null;
    final otherModeEntries = importing
        ? ref.watch(otherModeSubscriptionsProvider)
        : null;
    final currentEntries = importing
        ? (ref.watch(subscriptionEntriesProvider).value ??
              const <SubscriptionEntry>[])
        : const <SubscriptionEntry>[];
    final template = _selectedTemplate(templates);

    return CommonScaffold(
      title: title,
      isLoading: _submitting,
      confirmationAction: IconButtonData(
        glyph: TablerIcons.check,
        tooltip: context.l10n.subsSaveTooltip,
        onPressed: _submitting ? null : _submit,
      ),
      body: PageBody(
        children: [
          if (!_isEdit)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _MethodPicker(value: _method, onChanged: _changeMethod),
            ),
          if (_formError case final message?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: InlineNotice(
                message: message,
                glyph: TablerIcons.alert_circle,
                color: context.colorScheme.errorContainer,
                foregroundColor: context.colorScheme.onErrorContainer,
              ),
            ),
          if (_localWarning case final warning?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: InlineNotice(message: warning),
            ),
          if (importing)
            _OtherModeImportSection(
              modeLabel: _modeLabel(otherMode!, context.l10n),
              snapshot: otherModeEntries!,
              selectedKeys: _selectedKeys,
              currentKeys: {
                for (final entry in currentEntries)
                  subscriptionEntryKey(entry.record),
              },
              onToggle: (entry, selected) {
                final key = subscriptionEntryKey(entry.record);
                setState(() {
                  if (selected) {
                    _selectedKeys.add(key);
                  } else {
                    _selectedKeys.remove(key);
                  }
                });
              },
              onSelectAll: (selected) {
                final keys = {
                  for (final entry in otherModeEntries.value ?? const [])
                    if (!currentEntries.any(
                      (current) =>
                          subscriptionEntryKey(current.record) ==
                          subscriptionEntryKey(entry.record),
                    ))
                      subscriptionEntryKey(entry.record),
                };
                setState(() {
                  _selectedKeys.clear();
                  if (selected) {
                    _selectedKeys.addAll(keys);
                  }
                });
              },
            )
          else ...[
            _SheetCard(
              title: context.l10n.subsInfoSection,
              footer: _infoHint(isLocal),
              children: [
                if (isLocal) ...[
                  ListItem(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: const Icon(TablerIcons.file_import, size: 20),
                    title: Text(
                      _localName ??
                          (_isEdit
                              ? context.l10n.subsLocalRuleFile
                              : context.l10n.subsPickFile),
                    ),
                    subtitle: Text(
                      _isEdit
                          ? context.l10n.subsLocalFileSubscription
                          : (_localName == null
                                ? context.l10n.subsLocalFileHint
                                : context.l10n.subsLocalFileRepick),
                    ),
                    trailing: _isEdit
                        ? null
                        : TonalButton(
                            size: TonalButtonSize.compact,
                            label: _localName == null
                                ? context.l10n.subsChoose
                                : context.l10n.subsChange,
                            onPressed: _picking ? null : _pickFile,
                          ),
                    onTap: _isEdit || _picking ? null : _pickFile,
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
                        onChanged: (_) => setState(() {}),
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
