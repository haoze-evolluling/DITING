library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/native/platform_bridge.dart';
import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/data/subscriptions/subscription_url.dart';
import 'package:diting_android/pages/server/server_subscription_common.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/chip_row.dart';
import 'package:diting_android/widgets/notice.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

part 'server_subscription_edit_widgets.dart';

enum _SubMethod { remote, local }

class ServerSubscriptionEditPage extends ConsumerStatefulWidget {
  const ServerSubscriptionEditPage({super.key, this.listId});

  /// 为空表示新增。
  final String? listId;

  @override
  ConsumerState<ServerSubscriptionEditPage> createState() =>
      _ServerSubscriptionEditPageState();
}

class _ServerSubscriptionEditPageState
    extends ConsumerState<ServerSubscriptionEditPage> {
  final _name = TextEditingController();
  final _url = TextEditingController();

  var _method = _SubMethod.remote;
  var _kind = 'domain';
  var _group = '';
  String? _mirrorTemplate;
  var _mirrorFallback = true;

  String? _localName;
  String? _localText;
  String? _localPath;

  String? _formError;
  var _submitting = false;
  var _initialized = false;

  bool get _isEdit => widget.listId != null;

  ServerConfig? get _config =>
      ref.read(serverControllerProvider).value?.config;

  ServerFilterList? get _existing {
    final id = widget.listId;
    if (id == null) return null;
    for (final list in _config?.filter.lists ?? const <ServerFilterList>[]) {
      if (list.id == id) return list;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fill());
  }

  void _fill() {
    if (_initialized || !mounted) return;
    final list = _existing;
    if (_isEdit && list == null) {
      setState(() {
        _initialized = true;
        _formError = context.l10n.subscriptionNotFound;
      });
      return;
    }
    if (list != null) {
      _name.text = list.name;
      _url.text = list.isRemote ? list.url : '';
      _method = list.isRemote ? _SubMethod.remote : _SubMethod.local;
      _kind = list.kind;
      _group = list.group;
      _mirrorTemplate = list.mirrorTemplate.isEmpty ? null : list.mirrorTemplate;
      _mirrorFallback = list.mirrorFallback;
      if (!list.isRemote) {
        _localPath = list.url;
        _localName = serverListDisplayTarget(list);
      }
    }
    setState(() => _initialized = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final bridge = PlatformBridge();
    final picked = await bridge.pickPersistableTextFile();
    if (!mounted || picked.cancelled) return;
    if (picked.error != null) {
      setState(() => _formError = picked.error);
      return;
    }
    final name = picked.displayName;
    if (!name.toLowerCase().endsWith('.txt')) {
      setState(() => _formError = context.l10n.subsPickTxt);
      return;
    }
    var text = picked.text;
    final uri = picked.uri;
    if (text == null && uri != null) {
      final read = await bridge.readPersistedText(uri);
      if (!mounted) return;
      if (!read.isOk) {
        setState(
          () => _formError =
              read.error ?? context.l10n.subscriptionLocalFileUnreadable,
        );
        return;
      }
      text = read.text;
    }
    if (text == null) {
      setState(() => _formError = context.l10n.subscriptionLocalFileUnreadable);
      return;
    }
    setState(() {
      _localName = name;
      _localText = text;
      _formError = null;
      if (_name.text.trim().isEmpty) {
        _name.text = name.substring(0, name.length - 4);
      }
    });
  }

  Future<void> _createGroup() async {
    final name = await showFloatingDialog<String>(
      context: context,
      child: InputDialog(
        title: context.l10n.subsNewGroupTitle,
        value: '',
        validator: (value) =>
            (value ?? '').trim().isEmpty ? context.l10n.subsGroupNameRequired : null,
      ),
    );
    if (name != null && mounted) {
      setState(() => _group = name.trim());
    }
  }

  Future<void> _editMirror(List<String> templates) async {
    final choice = await showSheet<_TemplateChoice>(
      context: context,
      builder: (_) => _TemplateSheet(
        templates: templates,
        selected: _mirrorTemplate,
      ),
    );
    if (choice == null || !mounted) return;
    if (choice.add) {
      final raw = await showFloatingDialog<String>(
        context: context,
        child: InputDialog(
          title: context.l10n.subsAddMirrorTemplate,
          value: '',
          hintText: 'https://mirror.example.com/{url}',
          validator: (value) => (value ?? '').trim().isEmpty
              ? context.l10n.subsGroupNameRequired
              : null,
        ),
      );
      if (raw == null || !mounted) return;
      _saveTemplate(raw);
      return;
    }
    if (choice.delete != null) {
      _removeTemplate(choice.delete!);
      return;
    }
    setState(() => _mirrorTemplate = choice.value);
  }

  Future<void> _saveTemplate(String raw) async {
    String? normalized;
    try {
      normalized = normalizeMirrorTemplate(raw);
    } on FormatException catch (error) {
      setState(() => _formError = error.message);
      return;
    }
    if (normalized == null) return;
    final config = _config;
    if (config == null) return;
    final templates = [...config.mirrorTemplates];
    if (!templates.contains(normalized)) {
      templates.add(normalized);
    }
    try {
      await ref
          .read(serverControllerProvider.notifier)
          .saveConfig(config.copyWith(mirrorTemplates: templates));
      if (!mounted) return;
      setState(() => _mirrorTemplate = normalized);
    } catch (error) {
      if (mounted) setState(() => _formError = error.toString());
    }
  }

  Future<void> _removeTemplate(String template) async {
    final config = _config;
    if (config == null) return;
    try {
      await ref
          .read(serverControllerProvider.notifier)
          .saveConfig(
            config.copyWith(
              mirrorTemplates: [
                for (final item in config.mirrorTemplates)
                  if (item != template) item,
              ],
            ),
          );
      if (mounted && _mirrorTemplate == template) {
        setState(() => _mirrorTemplate = null);
      }
    } catch (error) {
      if (mounted) setState(() => _formError = error.toString());
    }
  }

  Future<void> _submit() async {
    final config = _config;
    if (config == null || _submitting) return;
    final existing = _existing;
    final isRemote = _isEdit
        ? existing?.isRemote ?? true
        : _method == _SubMethod.remote;
    final url = _url.text.trim();
    final name = _name.text.trim();

    if (isRemote) {
      final urlError = validateSubscriptionUrl(url);
      if (urlError != null) {
        setState(() => _formError = urlError);
        return;
      }
    } else if (!_isEdit && _localText == null) {
      setState(() => _formError = context.l10n.subscriptionPickRuleFile);
      return;
    }

    String? mirrorUrl;
    if (isRemote && _mirrorTemplate != null) {
      try {
        mirrorUrl = buildMirrorUrl(_mirrorTemplate!, url);
      } on FormatException catch (error) {
        setState(() => _formError = error.message);
        return;
      }
    }

    setState(() {
      _submitting = true;
      _formError = null;
    });
    final id = existing?.id ?? 'list-${DateTime.now().microsecondsSinceEpoch}';
    var target = url;
    try {
      if (!isRemote) {
        final text = _localText;
        if (text != null) {
          target = await copyServerLocalRuleFile(id: id, text: text);
        } else {
          target = _localPath ?? '';
        }
        if (target.isEmpty) {
          if (mounted) {
            setState(() {
              _submitting = false;
              _formError = context.l10n.subscriptionLocalFileUnreadable;
            });
          }
          return;
        }
      }

      final base =
          existing ??
          const ServerFilterList(id: '', name: '', url: '', enabled: true);
      var next = base.copyWith(
        id: id,
        name: name.isEmpty
            ? (isRemote
                  ? extractNameFromUrl(url)
                  : serverListDisplayTarget(base.copyWith(url: target)))
            : name,
        url: target,
        kind: _kind,
        group: _group.trim(),
        sourceType: isRemote ? 'remote' : 'local',
        mirrorTemplate: isRemote ? (_mirrorTemplate ?? '') : '',
        mirrorUrl: mirrorUrl ?? '',
        mirrorFallback: _mirrorFallback,
      );
      next = resetServerListMetrics(
        next,
        url: target,
        kind: _kind,
        sourceType: next.sourceType,
        mirrorUrl: next.mirrorUrl,
      );
      final lists = [
        for (final list in config.filter.lists)
          if (list.id != id) list,
        next,
      ];
      await ref
          .read(serverControllerProvider.notifier)
          .saveConfig(
            config.copyWith(filter: config.filter.copyWith(lists: lists)),
          );
      final running =
          ref.read(serverControllerProvider).value?.status.running == true;
      if (running) {
        try {
          await ref.read(serverControllerProvider.notifier).refreshFilter(id);
        } catch (_) {
          await ref.read(serverControllerProvider.notifier).refreshConfig();
        }
      }
      if (mounted) {
        showAppSnack(context, context.l10n.serverSubsSaved);
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _formError = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    if (config == null) {
      return CommonScaffold(
        title: _isEdit ? context.l10n.subsEdit : context.l10n.subsAdd,
        body: const Center(child: CommonCircleLoading()),
      );
    }
    if (!_initialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fill());
    }
    final existing = _existing;
    final isRemote = _isEdit
        ? existing?.isRemote ?? true
        : _method == _SubMethod.remote;
    final groups = <String>{};
    for (final list in config.filter.lists) {
      if (list.group.isNotEmpty) groups.add(list.group);
    }
    if (_group.isNotEmpty) groups.add(_group);
    final sortedGroups = groups.toList()..sort();
    final preview = _mirrorTemplate == null || _url.text.trim().isEmpty
        ? null
        : _tryBuildMirror();

    return CommonScaffold(
      title: _isEdit ? context.l10n.subsEdit : context.l10n.subsAdd,
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
              child: SegmentedControl<_SubMethod>(
                segments: [
                  (_SubMethod.remote, context.l10n.subsMethodRemote),
                  (_SubMethod.local, context.l10n.subsMethodLocal),
                ],
                value: _method,
                onChanged: (value) => setState(() {
                  _method = value;
                  _formError = null;
                }),
              ),
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
          _SheetCard(
            title: context.l10n.subsInfoSection,
            footer: isRemote
                ? context.l10n.serverSubsRunningHint
                : context.l10n.subsEditLocalHint,
            children: [
              if (!isRemote) ...[
                ListItem(
                  leading: const Icon(TablerIcons.file_import, size: 20),
                  title: Text(
                    _localName ?? context.l10n.subsLocalRuleFile,
                  ),
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
                    onPressed: _pickFile,
                  ),
                  onTap: _pickFile,
                ),
                _Field(
                  label: context.l10n.subsNameOptional,
                  child: _nameField(context.l10n.subsNameEmptyFileName),
                ),
              ] else ...[
                _Field(
                  label: context.l10n.subsUrl,
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
                _Field(
                  label: context.l10n.subsNameOptional,
                  child: _nameField(context.l10n.subsNameEmptyUrlTail),
                ),
              ],
            ],
          ),
          if (isRemote)
            _SheetCard(
              title: context.l10n.subsMirrorTitle,
              footer: context.l10n.subsMirrorFooter,
              children: [
                ListItem(
                  leading: const Icon(TablerIcons.flip_horizontal, size: 20),
                  title: Text(context.l10n.subsMirrorTemplate),
                  subtitle: Text(
                    _mirrorTemplate ?? context.l10n.serverSubsMirrorOff,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(TablerIcons.chevron_right, size: 18),
                  onTap: () => _editMirror(config.mirrorTemplates),
                ),
                if (_mirrorTemplate != null) ...[
                  ListItem.toggle(
                    leading: const Icon(TablerIcons.rotate_clockwise, size: 20),
                    title: Text(context.l10n.subsMirrorFallback),
                    subtitle: Text(context.l10n.subsMirrorFallbackSubtitle),
                    value: _mirrorFallback,
                    onChanged: (value) =>
                        setState(() => _mirrorFallback = value),
                  ),
                  if (preview != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Text(
                        '${context.l10n.subsEffectiveUrl}\n$preview',
                        style: AppTextRole.supportingText
                            .of(context)
                            .copyWith(fontFeatures: appTabularFigures),
                      ),
                    ),
                ],
              ],
            ),
          _SheetCard(
            title: context.l10n.subsRuleType,
            children: [
              ListItem<String>.options(
                leading: const Icon(TablerIcons.list_details, size: 20),
                title: Text(context.l10n.subsKindLabel),
                subtitle: Text(
                  _kind == 'hosts'
                      ? context.l10n.subsKindHostsHint
                      : _kind == 'all'
                      ? context.l10n.subscriptionKindAllHint
                      : context.l10n.subsKindDomainHint,
                ),
                value: _kind,
                options: const ['domain', 'hosts', 'all'],
                textBuilder: (value) => switch (value) {
                  'hosts' => context.l10n.subscriptionKindHosts,
                  'all' => context.l10n.subscriptionKindAll,
                  _ => context.l10n.subscriptionKindDomain,
                },
                onChanged: (value) => setState(() => _kind = value),
              ),
              _Field(
                label: context.l10n.subsGroupLabel,
                hint: context.l10n.subsGroupHint,
                child: ChipRow(
                  children: [
                    FilterPill(
                      label: context.l10n.subscriptionUngrouped,
                      selected: _group.isEmpty,
                      onPressed: () => setState(() => _group = ''),
                    ),
                    for (final group in sortedGroups)
                      FilterPill(
                        label: group,
                        selected: _group == group,
                        onPressed: () => setState(() => _group = group),
                      ),
                    TonalChip(
                      label: context.l10n.subsGroupShort,
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String? _tryBuildMirror() {
    try {
      return buildMirrorUrl(_mirrorTemplate!, _url.text.trim());
    } on FormatException {
      return null;
    }
  }

  Widget _nameField(String hint) {
    return TextFormField(
      controller: _name,
      textInputAction: TextInputAction.done,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(hintText: hint),
    );
  }
}


