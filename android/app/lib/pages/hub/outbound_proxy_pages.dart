import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/apps_bridge.dart';
import 'package:diting_android/data/native/outbound_proxy_bridge.dart';
import 'package:diting_android/routes/hub_routes.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_android/state/outbound_proxy_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_icon_avatar.dart';
import 'package:diting_android/widgets/app_snack.dart';
import 'package:diting_android/widgets/app_list_error_state.dart';
import 'package:diting_android/widgets/app_list_view.dart';
import 'package:diting_android/widgets/section_slivers.dart';
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
    _bump();
  }

  void _bump() => ref.read(outboundProxyRevisionProvider.notifier).bump();

  /// Persists a config change and, when given, the matching engine status.
  Future<void> _persist(OutboundProxyConfig config, {String? status}) async {
    final store = ref.read(outboundProxyStoreProvider);
    await store.write(config);
    if (status != null) {
      await store.setStatus(status, '');
    }
    _bump();
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
      showAppSnack(context, error);
      return;
    }
    setState(() => _saving = true);
    try {
      await _persist(draft, status: draft.enabled ? 'connecting' : 'disabled');
      _loaded = draft;
      if (mounted) showAppSnack(context, l10n.outboundSaved);
    } on Object catch (error) {
      if (mounted) showAppSnack(context, l10n.outboundSaveFailed('$error'));
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
    _bump();
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
    showAppSnack(context, context.l10n.outboundResetDone);
  }

  Set<String>? _installedPackages() {
    final snapshot = ref.read(installedAppsProvider).value;
    // Null when the list is unavailable (missing channel), so `validationError` skips the
    // "not installed" check instead of failing a valid package.
    return snapshot == null || snapshot.error != null
        ? null
        : snapshot.packageNames;
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
                    : (value) => _persist(
                        // As upstream: the switch persists immediately and moves to
                        // connecting or disabled; other fields wait for save.
                        config.copyWith(enabled: value),
                        status: value ? 'connecting' : 'disabled',
                      ),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.appsList),
                title: Text(context.l10n.outboundApp),
                subtitle: Text(
                  config.proxyAppPackage.isEmpty
                      ? context.l10n.outboundNoApp
                      : appLabel,
                ),
                onTap: () => context.push('/hub/outbound-proxy/apps'),
              ),
            ],
            footer: _statusFooter(context.l10n, config),
          ),
          _scopeSection(context, config),
          const SizedBox(height: 12),
          generateSection(
            items: [
              ListItem<OutboundProxyProtocol>.options(
                leading: const GlyphIcon(AppGlyphs.link),
                title: Text(context.l10n.obsProtocol),
                value: config.protocol,
                options: OutboundProxyProtocol.values,
                textBuilder: (protocol) => protocol.label,
                onChanged: _saving
                    ? (_) {}
                    : (value) => _persist(config.copyWith(protocol: value)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Expanded(
                  flex: 2,
                  child: LabeledInputField(
                    label: context.l10n.outboundHostLabel,
                    controller: _host,
                    autocorrect: false,
                    helperText: context.l10n.outboundHostHelper,
                  ),
                ),
                Expanded(
                  child: LabeledInputField(
                    label: context.l10n.commonPort,
                    controller: _port,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: LabeledInputField(
              label: context.l10n.outboundUsernameLabel,
              controller: _username,
              autocorrect: false,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: LabeledInputField(
              label: context.l10n.outboundPasswordLabel,
              controller: _password,
              obscureText: true,
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
    return generateSection(
      title: l10n.outboundScopeTitle,
      items: [
        ListItem<OutboundProxyScope>.options(
          leading: const GlyphIcon(AppGlyphs.appsList),
          title: Text(l10n.outboundScopeTitle),
          value: config.scope,
          options: OutboundProxyScope.values,
          textBuilder: (scope) => scope == OutboundProxyScope.apps
              ? l10n.outboundScopeApps
              : l10n.outboundScopeAll,
          onChanged: _saving
              ? (_) {}
              : (value) => _persist(config.copyWith(scope: value)),
        ),
        if (perApp)
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
      ],
      footer: perApp
          ? l10n.outboundScopeAppsFooter
          : l10n.outboundScopeAllFooter,
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
      'error' =>
        config.statusMessage.isEmpty
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
