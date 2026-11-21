import 'package:diting_android/data/server/server_models.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/unsaved_changes.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ServerFilterRulesPage extends ConsumerStatefulWidget {
  const ServerFilterRulesPage({super.key});

  @override
  ConsumerState<ServerFilterRulesPage> createState() =>
      _ServerFilterRulesPageState();
}

class _ServerFilterRulesPageState extends ConsumerState<ServerFilterRulesPage> {
  final _rules = TextEditingController();
  String _savedText = '';
  bool _ready = false;

  @override
  void dispose() {
    _rules.dispose();
    super.dispose();
  }

  void _fill(ServerFilterConfig filter) {
    if (_ready) return;
    _savedText = _normalized(filter.customRules.join('\n'));
    _rules.text = _savedText;
    _ready = true;
  }

  String _normalized(String value) => value
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join('\n');

  bool get _hasChanges => _ready && _normalized(_rules.text) != _savedText;

  Future<bool> _save(ServerConfig config, ServerFilterConfig filter) async {
    final rules = _normalized(_rules.text).isEmpty
        ? const <String>[]
        : _normalized(_rules.text).split('\n');
    try {
      await ref
          .read(serverControllerProvider.notifier)
          .saveConfig(
            config.copyWith(filter: filter.copyWith(customRules: rules)),
          );
      if (!mounted) return false;
      setState(() {
        _savedText = rules.join('\n');
        _rules.text = _savedText;
      });
      showAppSnack(context, context.l10n.serverFilterSaved);
      return true;
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
      return false;
    }
  }

  Future<bool> _resolve(ServerConfig config, ServerFilterConfig filter) async {
    final choice = await showUnsavedChangesDialog(context);
    return switch (choice) {
      UnsavedChangesChoice.discard => true,
      UnsavedChangesChoice.save => _save(config, filter),
      UnsavedChangesChoice.cancel => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(serverControllerProvider).value;
    if (snapshot == null) {
      return CommonScaffold(
        title: context.l10n.serverCustomRules,
        body: const Center(child: CommonCircleLoading()),
      );
    }
    final config = snapshot.config;
    final filter = config.filter;
    _fill(filter);
    return ListenableBuilder(
      listenable: _rules,
      builder: (context, _) => UnsavedChangesScope(
        hasUnsavedChanges: () => _hasChanges,
        onResolve: () => _resolve(config, filter),
        child: CommonScaffold(
          title: context.l10n.serverCustomRules,
          backAction: () async {
            if (!_hasChanges || await _resolve(config, filter)) {
              if (context.mounted) Navigator.of(context).pop();
            }
          },
          primaryAction: IconButtonData(
            glyph: TablerIcons.check,
            tooltip: context.l10n.commonSave,
            onPressed: () => _save(config, filter),
          ),
          body: PageBody(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: CommonCard(
                  padding: const EdgeInsets.all(14),
                  child: LabeledInputField(
                    label: context.l10n.serverCustomRulesContent,
                    controller: _rules,
                    hintText: context.l10n.serverCustomRulesHint,
                    minLines: 8,
                    maxLines: 16,
                    autocorrect: false,
                    helperText: context.l10n.serverCustomRulesNote,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
