import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/apps_bridge.dart';
import 'package:diting_android/data/native/outbound_proxy_bridge.dart';
import 'package:diting_android/routes/hub_routes.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_android/state/outbound_proxy_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_icon_avatar.dart';
import 'package:diting_android/widgets/app_list_error_state.dart';
import 'package:diting_android/widgets/app_list_view.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

part 'outbound_proxy_apps_page.dart';

/// DITING's own package id (`applicationId` in `android/app/build.gradle.kts`).
/// Upstream reads `context.packageName`; this constant must match or the "cannot select
/// DITING itself" check breaks.
const ditingSelfPackage = 'com.haoze.diting';

/// Outbound proxy (upstream `OutboundProxySettingsScreen`). Config goes through
/// `OutboundProxyStore`, so initial values arrive asynchronously from
/// `outboundProxyConfigProvider`; a save bumps its revision.
class OutboundProxyPage extends ConsumerStatefulWidget {
  const OutboundProxyPage({super.key});

  @override
  ConsumerState<OutboundProxyPage> createState() => _OutboundProxyPageState();
}

class _OutboundProxyPageState extends ConsumerState<OutboundProxyPage> {
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  /// Filled once: another `read()` would overwrite what the user is typing.
  OutboundProxyConfig? _loaded;
  bool _saving = false;

  /// Status polling, as upstream's one-second loop: `outbound_proxy_status` goes connecting
  /// -> ready or error once the tunnel starts.
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Re-reads the store only while the tunnel may still come up; `ready`, `error` and
  /// `disabled` are terminal, so polling them only causes rebuilds.
  void _tick() {
    if (!mounted) {
      return;
    }
    final config = ref.read(outboundProxyConfigProvider).value;
    if (config == null || !config.enabled || config.status != 'connecting') {
      return;
    }
    ref.read(outboundProxyRevisionProvider.notifier).bump();
  }

  void _adopt(OutboundProxyConfig config) {
    if (_loaded != null) {
      return;
    }
    _loaded = config;
    _host.text = config.host;
    _port.text = '${config.port}';
    _username.text = config.username;
    _password.text = config.password;
  }

  OutboundProxyConfig _compose(OutboundProxyConfig base) => base.copyWith(
    host: _host.text.trim(),
    port: int.tryParse(_port.text.trim()) ?? 0,
    username: _username.text,
    password: _password.text,
  );

  Future<void> _save(OutboundProxyConfig base) async {
    final l10n = context.l10n;
    final draft = _compose(base);
    // Upstream skips validation while disabled, or a disabled draft could never be saved.
    final error = draft.enabled
        ? draft.validationError(
            selfPackage: ditingSelfPackage,
            installedPackages: _installedPackages(),
          )
        : null;
    if (error != null) {
      _toast(error);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(outboundProxyStoreProvider).write(draft);
      await ref
          .read(outboundProxyStoreProvider)
          .setStatus(draft.enabled ? 'connecting' : 'disabled', '');
      ref.read(outboundProxyRevisionProvider.notifier).bump();
      _loaded = draft;
      _toast(l10n.outboundSaved);
    } on Object catch (error) {
      _toast(l10n.outboundSaveFailed('$error'));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _reset() async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.outboundResetTitle,
        destructive: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.uiCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.uiReset),
          ),
        ],
        child: Text(context.l10n.outboundResetBody),
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await ref.read(outboundProxyStoreProvider).reset();
    ref.read(outboundProxyRevisionProvider.notifier).bump();
    if (!mounted) {
      return;
    }
    setState(() {
      _loaded = null;
      _host.clear();
      _port.clear();
      _username.clear();
      _password.clear();
    });
    _toast(context.l10n.outboundResetDone);
  }

  Set<String>? _installedPackages() {
    final snapshot = ref.read(installedAppsProvider).value;
    // Null when the list is unavailable (missing channel), so `validationError` skips the
    // "not installed" check instead of failing a valid package.
    return snapshot == null || snapshot.error != null
        ? null
        : snapshot.packageNames;
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncConfig = ref.watch(outboundProxyConfigProvider);
    final config = asyncConfig.value;
    if (config == null) {
      return CommonScaffold(
        title: context.l10n.hubOutboundProxy,
        body: const Center(child: CommonCircleLoading.page()),
      );
    }
    _adopt(config);
    final apps = ref.watch(installedAppsProvider).value;
    final appLabel = _labelOf(
      context.l10n,
      config.proxyAppPackage,
      apps?.apps ?? const [],
    );
    // Validation problems are shown only while enabled, matching upstream.
    final validation = config.enabled
        ? _compose(config).validationError(
            selfPackage: ditingSelfPackage,
            installedPackages: _installedPackages(),
          )
        : null;
    final colorScheme = context.colorScheme;
    return CommonScaffold(
      title: context.l10n.hubOutboundProxy,
      menuItems: [
        CommonPopupMenuItem(
          label: context.l10n.outboundResetMenu,
          glyph: AppGlyphs.reset,
          danger: true,
          onPressed: _saving ? null : _reset,
        ),
      ],
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.outboundSectionProxy,
            items: [
              ListItem.toggle(
                leading: const GlyphIcon(AppGlyphs.link),
                title: Text(context.l10n.outboundEnable),
                subtitle: Text(
                  _statusLabel(context.l10n, config),
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: _statusColor(context, config)),
                ),
                value: config.enabled,
                onChanged: _saving
                    ? null
                    : (value) async {
                        // As upstream: the switch persists immediately and moves to
                        // connecting or disabled; other fields wait for save.
                        final next = config.copyWith(enabled: value);
                        await ref.read(outboundProxyStoreProvider).write(next);
                        await ref
                            .read(outboundProxyStoreProvider)
                            .setStatus(value ? 'connecting' : 'disabled', '');
                        ref.read(outboundProxyRevisionProvider.notifier).bump();
                      },
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.appsList),
                title: Text(context.l10n.outboundApp),
                subtitle: Text(
                  config.proxyAppPackage.isEmpty ? context.l10n.outboundNoApp : appLabel,
                ),
                onTap: () => context.push('/hub/outbound-proxy/apps'),
              ),
            ],
            footer: _statusFooter(context.l10n, config),
          ),
          _scopeSection(context, config),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: SegmentedControl<OutboundProxyProtocol>(
              segments: [
                for (final protocol in OutboundProxyProtocol.values)
                  (protocol, protocol.label),
              ],
              value: config.protocol,
              onChanged: _saving
                  ? (_) {}
                  : (value) async {
                      await ref
                          .read(outboundProxyStoreProvider)
                          .write(config.copyWith(protocol: value));
                      ref.read(outboundProxyRevisionProvider.notifier).bump();
                    },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _host,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: context.l10n.outboundHostLabel,
                      helperText: context.l10n.outboundHostHelper,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: context.l10n.serverPort),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _username,
              autocorrect: false,
              decoration: InputDecoration(labelText: context.l10n.outboundUsernameLabel),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(labelText: context.l10n.outboundPasswordLabel),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ListFooter(
              text: config.protocol == OutboundProxyProtocol.http
                  ? context.l10n.outboundHttpFooter
                  : context.l10n.outboundSocksFooter,
            ),
          ),
          if (validation != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: CommonCard(
                padding: const EdgeInsets.all(12),
                child: Text(
                  validation,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: colorScheme.error),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TonalButton(
              label: context.l10n.commonSave,
              onPressed: _saving ? null : () => _save(config),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Proxy scope: all apps (original behaviour) or only the picked target apps.
  Widget _scopeSection(BuildContext context, OutboundProxyConfig config) {
    final l10n = context.l10n;
    final perApp = config.scope == OutboundProxyScope.apps;
    final count = config.effectiveTargets.length;
    // The segmented control sits outside the card group, so the target row is a lone card
    // with all four corners rounded.
    return Column(
      children: [
        ListHeader(title: l10n.outboundScopeTitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedControl<OutboundProxyScope>(
            segments: [
              (OutboundProxyScope.all, l10n.outboundScopeAll),
              (OutboundProxyScope.apps, l10n.outboundScopeApps),
            ],
            value: config.scope,
            onChanged: _saving
                ? (_) {}
                : (value) async {
                    await ref
                        .read(outboundProxyStoreProvider)
                        .write(config.copyWith(scope: value));
                    ref.read(outboundProxyRevisionProvider.notifier).bump();
                  },
          ),
        ),
        if (perApp)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: generateGroup([
              ListItem(
                leading: const GlyphIcon(AppGlyphs.appsList),
                title: Text(l10n.outboundTargets),
                subtitle: Text(
                  count == 0
                      ? l10n.appSelectionNoAppsYet
                      : l10n.appSelectionCount('$count'),
                ),
                onTap: () => context.push(HubPaths.outboundProxyTargets),
              ),
            ]),
          ),
        ListFooter(
          text: perApp ? l10n.outboundScopeAppsFooter : l10n.outboundScopeAllFooter,
        ),
      ],
    );
  }

  /// The four engine states: disabled, connecting, ready and error. Unknown values display
  /// as disabled, as upstream does.
  static String _statusLabel(AppL10n l10n, OutboundProxyConfig config) {
    if (!config.enabled) {
      return l10n.outboundStatusOff;
    }
    return switch (config.status) {
      'connecting' => l10n.outboundStatusConnecting,
      'ready' => l10n.outboundStatusReady,
      'error' => config.statusMessage.isEmpty
          ? l10n.outboundStatusFailed
          : config.statusMessage,
      _ => l10n.outboundStatusOff,
    };
  }

  static Color _statusColor(BuildContext context, OutboundProxyConfig config) {
    final colorScheme = context.colorScheme;
    if (!config.enabled) {
      return colorScheme.onSurfaceVariant;
    }
    return switch (config.status) {
      'ready' => colorScheme.success,
      'error' => colorScheme.error,
      'connecting' => colorScheme.primary,
      _ => colorScheme.onSurfaceVariant,
    };
  }

  static String? _statusFooter(AppL10n l10n, OutboundProxyConfig config) {
    if (!config.enabled) {
      return null;
    }
    return switch (config.status) {
      'error' => l10n.outboundFooterError,
      'ready' => l10n.outboundFooterReady,
      'connecting' => l10n.outboundFooterConnecting,
      _ => null,
    };
  }

  static String _labelOf(
    AppL10n l10n,
    String packageName,
    List<InstalledApp> apps,
  ) {
    if (packageName.isEmpty) {
      return l10n.outboundNoApp;
    }
    for (final app in apps) {
      if (app.packageName == packageName) {
        return app.label;
      }
    }
    return packageName;
  }
}
