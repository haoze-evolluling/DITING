import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/state/server_providers.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ServerFilterTestPage extends ConsumerStatefulWidget {
  const ServerFilterTestPage({super.key});

  @override
  ConsumerState<ServerFilterTestPage> createState() =>
      _ServerFilterTestPageState();
}

class _ServerFilterTestPageState extends ConsumerState<ServerFilterTestPage> {
  final _domain = TextEditingController();
  ServerFilterCheck? _result;
  bool _checking = false;

  @override
  void dispose() {
    _domain.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final domain = _domain.text.trim();
    if (domain.isEmpty) {
      showAppSnack(context, context.l10n.serverCheckDomainRequired);
      return;
    }
    setState(() => _checking = true);
    try {
      final result = await ref.read(serverClientProvider).filterCheck(domain);
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) showAppSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.l10n.serverFilterTestTitle,
      body: PageBody(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: CommonCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  LabeledInputField(
                    label: context.l10n.serverCheckDomain,
                    controller: _domain,
                    hintText: 'ads.example.com',
                    autocorrect: false,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _check(),
                  ),
                  TonalButton(
                    label: _checking
                        ? context.l10n.serverCheckChecking
                        : context.l10n.serverCheckAction,
                    glyph: AppGlyphs.target,
                    onPressed: _checking ? null : _check,
                  ),
                ],
              ),
            ),
          ),
          if (_result case final result?)
            generateSection(
              title: context.l10n.serverCheckResult,
              items: [
                ListItem(
                  leading: GlyphIcon(
                    result.blocked ? AppGlyphs.block : AppGlyphs.checkCircle,
                    size: 20,
                  ),
                  title: Text(
                    result.blocked
                        ? context.l10n.serverCheckBlocked
                        : context.l10n.serverCheckAllowed,
                  ),
                  subtitle: Text(
                    [
                      if (result.matchedRule.isNotEmpty) result.matchedRule,
                      if (result.listName.isNotEmpty) result.listName,
                      if (result.reason.isNotEmpty) result.reason,
                    ].join(' · '),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
