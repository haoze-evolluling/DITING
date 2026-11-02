// ignore_for_file: sort_child_properties_last
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/agent/agent_api_client.dart';
import 'package:diting_android/data/agent/agent_api_text_parser.dart';
import 'package:diting_android/state/agent_providers.dart';
import 'package:diting_android/state/hub_settings_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ProviderFormResult {
  const ProviderFormResult({
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.key,
  });

  final String name;
  final String baseUrl;
  final String model;

  final String key;
}

/// Provider edit dialog: name, base URL, model, key plus two real actions - "fetch models"
/// calls `GET {base}/models`, "test connection" sends a minimal `chat/completions` request.
class AgentProviderEditor extends ConsumerStatefulWidget {
  const AgentProviderEditor({super.key, this.existing, this.preset});

  final AiProviderConfig? existing;
  final AiProviderPreset? preset;

  @override
  ConsumerState<AgentProviderEditor> createState() =>
      _AgentProviderEditorState();
}

class _AgentProviderEditorState extends ConsumerState<AgentProviderEditor> {
  late final _name = TextEditingController(
    text: widget.existing?.name ?? widget.preset?.name ?? '',
  );
  late final _baseUrl = TextEditingController(
    text: widget.existing?.baseUrl ?? widget.preset?.baseUrl ?? '',
  );
  late final _model = TextEditingController(text: widget.existing?.model ?? '');
  final _key = TextEditingController();
  String? _error;
  String? _notice;
  bool _busy = false;
  List<String> _models = const [];

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  String get _effectiveKey {
    final typed = _key.text.trim();
    if (typed.isNotEmpty) return typed;
    return widget.existing?.apiKey ?? '';
  }

  void _save() {
    final name = _name.text.trim();
    final baseUrl = _baseUrl.text.trim();
    final model = _model.text.trim();
    if (name.isEmpty || !baseUrl.startsWith('http') || model.isEmpty) {
      setState(() => _error = context.l10n.agentEditorErrorRequired);
      return;
    }
    Navigator.of(context).pop(
      ProviderFormResult(
        name: name,
        baseUrl: baseUrl,
        model: model,
        key: _key.text.trim(),
      ),
    );
  }

  Future<void> _fetchModels() async {
    if (_busy) return;
    final baseUrl = _baseUrl.text.trim();
    final key = _effectiveKey;
    if (baseUrl.isEmpty) {
      setState(() => _error = context.l10n.agentEditorErrorBaseUrl);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final models = await fetchAgentModels(ref, baseUrl: baseUrl, apiKey: key);
      if (!mounted) return;
      setState(() {
        _models = models;
        _busy = false;
        _notice = context.l10n.agentEditorFetched(models.length);
      });
    } on AgentApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.l10n.agentEditorFetchFailed('$error');
      });
    }
  }

  Future<void> _testConnection() async {
    if (_busy) return;
    final baseUrl = _baseUrl.text.trim();
    final key = _effectiveKey;
    final model = _model.text.trim();
    if (baseUrl.isEmpty || model.isEmpty) {
      setState(() => _error = context.l10n.agentEditorErrorTestNeeds);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await testAgentConnection(
        ref,
        AgentChatConfig(baseUrl: baseUrl, apiKey: key, model: model),
      );
      if (!mounted) return;
      final usage = result.hasUsage
          ? context.l10n.agentEditorUsage(result.totalTokens)
          : '';
      setState(() {
        _busy = false;
        _notice = context.l10n.agentEditorConnected('${result.model}$usage');
      });
    } on AgentApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.l10n.agentEditorConnectFailed('$error');
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final result = parseAgentApiText(data?.text ?? '');
    if (result.isEmpty) {
      setState(() {
        _error = null;
        _notice = result.message;
      });
      return;
    }
    setState(() {
      _error = null;
      if (result.baseUrl case final baseUrl? when baseUrl.isNotEmpty) {
        _baseUrl.text = baseUrl;
      }
      if (result.apiKey case final apiKey? when apiKey.isNotEmpty) {
        _key.text = apiKey;
      }
      if (result.model case final model? when model.isNotEmpty) {
        _model.text = model;
      }
      _notice = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonDialog(
      title: widget.existing == null ? context.l10n.agentEditorAddTitle : context.l10n.agentEditorEditTitle,
      hasFields: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _pasteFromClipboard,
              icon: const GlyphIcon(AppGlyphs.paste, size: 16),
              label: Text(context.l10n.agentEditorPaste),
            ),
          ),
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: context.l10n.agentEditorName),
          ),
          TextField(
            controller: _baseUrl,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: context.l10n.agentEditorBaseUrl,
              hintText: 'https://api.example.com/v1',
            ),
          ),
          TextField(
            controller: _model,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: context.l10n.agentEditorModel,
              hintText: context.l10n.agentEditorModelHint,
            ),
          ),
          TextField(
            controller: _key,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'API Key',
              helperText: widget.existing?.hasKey == true
                  ? context.l10n.agentEditorKeyKeep
                  : context.l10n.agentEditorKeyLocal,
            ),
          ),
          if (_models.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final model in _models)
                  TonalChip(
                    label: model,
                    color: model == _model.text.trim()
                        ? colorScheme.primaryContainer
                        : context.raisedSurfaceLevel.colorOf(colorScheme),
                    foregroundColor: model == _model.text.trim()
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                    onPressed: () => setState(() => _model.text = model),
                  ),
              ],
            ),
          Row(
            spacing: 8,
            children: [
              TonalButton(
                label: _busy ? context.l10n.agentEditorFetching : context.l10n.agentEditorFetch,
                glyph: AppGlyphs.cloudDownload,
                size: TonalButtonSize.section,
                onPressed: _busy ? null : _fetchModels,
              ),
              TonalButton(
                label: context.l10n.agentEditorTest,
                glyph: AppGlyphs.checkCircle,
                size: TonalButtonSize.section,
                onPressed: _busy ? null : _testConnection,
              ),
            ],
          ),
          if (_notice != null)
            Text(
              _notice!,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: colorScheme.success),
            ),
          if (_error != null)
            Text(
              _error!,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.uiCancel),
        ),
        TextButton(onPressed: _save, child: Text(context.l10n.commonSave)),
      ],
    );
  }
}
