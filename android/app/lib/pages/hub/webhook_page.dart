/// A11: outbound webhook settings — endpoint, HMAC secret and a signed test delivery.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/webhook/webhook_dispatcher.dart';
import 'package:diting_android/state/webhook_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../widgets/page_intro.dart';

class WebhookPage extends ConsumerStatefulWidget {
  const WebhookPage({super.key});

  @override
  ConsumerState<WebhookPage> createState() => _WebhookPageState();
}

class _WebhookPageState extends ConsumerState<WebhookPage> {
  late final TextEditingController _url;
  late final TextEditingController _secret;
  bool _obscure = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(webhookSettingsProvider);
    _url = TextEditingController(text: settings.url);
    _secret = TextEditingController(text: settings.secret);
  }

  @override
  void dispose() {
    _url.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(webhookSettingsProvider);
    final notifier = ref.read(webhookSettingsProvider.notifier);
    return CommonScaffold(
      title: l10n.webhookTitle,
      body: PageBody(
        children: [
          PageIntroCard(text: l10n.webhookIntro),
          generateSection(
            title: l10n.webhookSection,
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.send),
                title: Text(l10n.webhookEnable),
                subtitle: Text(l10n.webhookEnableDesc),
                trailing: Semantics(
                  label: l10n.webhookEnable,
                  child: Switch(
                    value: settings.enabled,
                    onChanged: notifier.setEnabled,
                  ),
                ),
              ),
              _Field(
                label: l10n.webhookUrl,
                hint: l10n.webhookUrlHint,
                child: TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(border: InputBorder.none),
                  onChanged: notifier.setUrl,
                ),
              ),
              _Field(
                label: l10n.webhookSecret,
                hint: l10n.webhookSecretDesc,
                child: TextField(
                  controller: _secret,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      tooltip: l10n.webhookSecret,
                      icon: const GlyphIcon(AppGlyphs.eyeOff, size: 20),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onChanged: notifier.setSecret,
                ),
              ),
            ],
          ),
          generateSection(
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.send),
                title: Text(l10n.webhookTest),
                subtitle: Text(
                  _testing ? l10n.webhookTesting : l10n.webhookTestHint,
                ),
                trailing: const GlyphIcon(AppGlyphs.chevronForward, size: 18),
                onTap: _testing || !settings.isConfigured ? null : _sendTest,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _sendTest() async {
    final l10n = context.l10n;
    setState(() => _testing = true);
    final WebhookDeliveryResult result;
    try {
      result = await ref.read(webhookActionsProvider).sendTest();
    } catch (error) {
      if (mounted) setState(() => _testing = false);
      _snack(l10n.webhookTestFail('$error'));
      return;
    }
    if (!mounted) return;
    setState(() => _testing = false);
    _snack(
      result.ok ? l10n.webhookTestOk(result.describe()) : l10n.webhookTestFail(result.describe()),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.hint, required this.child});

  final String label;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          CommonCard(child: child),
          const SizedBox(height: 4),
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
