/// Where the desktop app looks for the local service: host, port and token.
///
/// The old desktop console's `ServicePanel.vue` connection block is the blueprint. The keys are the
/// ones the Wails console wrote (`ipc_host` / `ipc_port` / `ipc_token`), so an existing install keeps
/// its address. Saving rewrites those keys and rebuilds the API client; testing pings the service the
/// app is currently using.
library;

import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/widgets/desktop_feedback.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ServiceConnectionCard extends ConsumerStatefulWidget {
  const ServiceConnectionCard({super.key});

  @override
  ConsumerState<ServiceConnectionCard> createState() =>
      _ServiceConnectionCardState();
}

class _ServiceConnectionCardState extends ConsumerState<ServiceConnectionCard> {
  late final _host = TextEditingController();
  late final _port = TextEditingController();
  late final _token = TextEditingController();
  bool _testing = false;
  bool _invalid = false;
  bool? _reachable;

  @override
  void initState() {
    super.initState();
    final config = ref.read(desktopApiConfigProvider);
    _host.text = config.host;
    _port.text = '${config.port}';
    _token.text = config.token;
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final l10n = context.l10n;
    setState(() => _testing = true);
    final bool ok;
    try {
      ok = await ref.read(desktopApiClientProvider).health();
    } on Object {
      if (mounted) {
        setState(() {
          _testing = false;
          _reachable = false;
        });
      }
      if (mounted) showDesktopMessage(context, l10n.desktopServiceUnreachable);
      return;
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _reachable = ok;
    });
    showDesktopMessage(
      context,
      ok ? l10n.desktopServiceReachable : l10n.desktopServiceUnreachable,
    );
  }

  void _save() {
    final l10n = context.l10n;
    final port = int.tryParse(_port.text);
    if (_host.text.trim().isEmpty || port == null || port < 1 || port > 65535) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    final store = ref.read(legacyPrefsStoreProvider);
    store.putString(desktopPrefsContainer, 'ipc_host', _host.text.trim());
    store.putInt(desktopPrefsContainer, 'ipc_port', port);
    store.putString(desktopPrefsContainer, 'ipc_token', _token.text.trim());
    ref.invalidate(desktopApiConfigProvider);
    showDesktopMessage(context, l10n.desktopServiceSaved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return DashboardCard(
      semanticLabel: l10n.desktopServiceConnectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.sync,
            title: l10n.desktopServiceConnectionTitle,
            leading: [
              DashboardChip(
                label: _reachable == null
                    ? l10n.desktopServiceConfigured
                    : _reachable!
                    ? l10n.desktopServiceReachable
                    : l10n.desktopServiceUnreachable,
                tone: _reachable == null
                    ? DashboardChipTone.idle
                    : _reachable!
                    ? DashboardChipTone.ok
                    : DashboardChipTone.warn,
                dot: _reachable ?? false,
              ),
            ],
            trailing: [
              if (_testing)
                const SizedBox.square(
                  dimension: 16,
                  child: CommonCircleLoading(),
                )
              else
                SizedBox(
                  height: 28,
                  child: DashboardIconButton(
                    glyph: AppGlyphs.sync,
                    tooltip: l10n.desktopServiceTest,
                    size: 28,
                    glyphSize: 15,
                    onPressed: () => unawaited(_test()),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopServiceConnectionBody,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 240,
                child: TextFormField(
                  controller: _host,
                  decoration: InputDecoration(
                    labelText: l10n.desktopServiceHost,
                    hintText: '127.0.0.1',
                  ),
                  style: AppTextStyle.callout.of(context).toMonospace,
                  onChanged: (_) => setState(() => _reachable = null),
                ),
              ),
              SizedBox(
                width: 150,
                child: TextFormField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l10n.desktopServicePort,
                    hintText: '15353',
                  ),
                  style: AppTextStyle.callout.of(context).toMonospace,
                  onChanged: (_) => setState(() => _reachable = null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _token,
            obscureText: true,
            decoration: InputDecoration(
              labelText: l10n.desktopServiceToken,
              hintText: l10n.desktopServiceTokenHint,
            ),
            style: AppTextStyle.callout.of(context).toMonospace,
            onChanged: (_) => setState(() => _reachable = null),
          ),
          if (_invalid) ...[
            const SizedBox(height: 6),
            Text(
              l10n.desktopServiceAddressInvalid,
              style: DashboardText.label(context, color: colorScheme.error),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: _testing ? null : () => unawaited(_test()),
                child: Text(l10n.desktopServiceTest),
              ),
              FilledButton.tonal(
                onPressed: _testing ? null : _save,
                child: Text(l10n.desktopServiceSave),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopServiceConnectionFooter,
            style: DashboardText.label(context),
          ),
        ],
      ),
    );
  }
}
