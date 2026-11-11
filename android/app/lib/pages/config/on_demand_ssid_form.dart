part of 'on_demand_page.dart';

/// Add or edit an SSID rule; an empty [existing] means a new rule.
Future<void> showSsidForm(
  BuildContext context,
  WidgetRef ref, {
  String? existing,
}) => showFormSheet<void>(
  context: context,
  builder: (_) => _SsidFormSheet(existing: existing),
);

class _SsidFormSheet extends ConsumerStatefulWidget {
  const _SsidFormSheet({this.existing});

  final String? existing;

  @override
  ConsumerState<_SsidFormSheet> createState() => _SsidFormSheetState();
}

class _SsidFormSheetState extends ConsumerState<_SsidFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _ssid = TextEditingController(text: widget.existing ?? '');
  late var _cellular = _initial?.cellular ?? true;
  late var _wifi = _initial?.wifi ?? true;
  late var _delay = _initial?.delayMs ?? 0;

  MockSsidRule? get _initial {
    for (final rule in ref.read(configResourcesProvider).ssidRules) {
      if (rule.ssid == widget.existing) {
        return rule;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _ssid.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    final ok = ref
        .read(configResourcesProvider.notifier)
        .putSsid(
          widget.existing,
          MockSsidRule(
            ssid: _ssid.text,
            cellular: _cellular,
            wifi: _wifi,
            delayMs: _delay,
          ),
        );
    if (!ok) {
      showConfigHint(context, context.l10n.ssidInvalid);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: widget.existing == null ? context.l10n.ssidAdd : context.l10n.ssidEdit,
      confirmationAction: IconButtonData(
        glyph: AppGlyphs.check,
        tooltip: context.l10n.ssidSave,
        onPressed: _submit,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          controller: sheetScrollController(context),
          padding: EdgeInsets.only(top: 8 + context.contentTopPadding),
          children: [
            generateSection(
              items: [
                ConfigFieldRow(
                  label: 'SSID',
                  hint: context.l10n.ssidHint,
                  child: TextFormField(
                    controller: _ssid,
                    autofocus: widget.existing == null,
                    decoration: InputDecoration(hintText: context.l10n.ssidExample),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? context.l10n.ssidEmptyError : null,
                  ),
                ),
              ],
            ),
            generateSection(
              title: context.l10n.ssidConnection,
              items: [
                ListItem.toggle(
                  title: Text(context.l10n.ssidCellular),
                  subtitle: Text(context.l10n.ssidCellularBody),
                  value: _cellular,
                  onChanged: (value) => setState(() => _cellular = value),
                ),
                ListItem.toggle(
                  title: const Text('Wi-Fi'),
                  subtitle: Text(context.l10n.ssidWifiBody),
                  value: _wifi,
                  onChanged: (value) => setState(() => _wifi = value),
                ),
              ],
              footer: context.l10n.ssidBothOff,
            ),
            generateSection(
              title: context.l10n.ssidDelay,
              items: [
                ListItem<int>.options(
                  title: Text(context.l10n.ssidStartDelay),
                  subtitle: Text(context.l10n.ssidStartDelayBody),
                  options: const [0, 500, 800, 1500, 3000],
                  value: [0, 500, 800, 1500, 3000].contains(_delay)
                      ? _delay
                      : 0,
                  textBuilder: (delay) => delay == 0 ? context.l10n.ssidImmediate : '$delay ms',
                  onChanged: (delay) => setState(() => _delay = delay),
                ),
              ],
            ),
            const DockSpacer(),
          ],
        ),
      ),
    );
  }
}
