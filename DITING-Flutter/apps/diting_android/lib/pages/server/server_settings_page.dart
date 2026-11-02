import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/pages/server/server_actions.dart';
import 'package:diting_android/pages/server/server_platform_probe.dart';
import 'package:diting_android/router.dart';
import 'package:diting_android/routes/hub_routes.dart';
import 'package:diting_android/state/server_status_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/nav_entry_row.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Server mode "settings" tab (upstream `server/ui/DnsSettingsScreen.kt`), five groups in upstream
/// order: proxy and resolution, rule management, data and reset, background stability, run mode.
class ServerSettingsPage extends ConsumerStatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  ConsumerState<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends ConsumerState<ServerSettingsPage> {
  BatteryOptimizationState _battery = BatteryOptimizationState.unavailable;
  bool _batteryLoaded = false;
  bool _clearingCache = false;

  @override
  void initState() {
    super.initState();
    _refreshBattery();
  }

  Future<void> _refreshBattery() async {
    final state = await readBatteryOptimization();
    if (!mounted) {
      return;
    }
    setState(() {
      _battery = state;
      _batteryLoaded = true;
    });
  }

  Future<void> _requestBattery() async {
    final state = await requestBatteryOptimization();
    if (!mounted) {
      return;
    }
    setState(() => _battery = state);
    if (state == BatteryOptimizationState.unavailable) {
      showServerHint(context, context.l10n.serverUnavailable);
      return;
    }
    showServerHint(
      context,
      state == BatteryOptimizationState.ignored ? context.l10n.serverBatteryJoined : context.l10n.serverBatteryNotJoined,
    );
  }

  Future<void> _clearCache() async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.serverClearCache,
        destructive: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.configCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.serverClear),
          ),
        ],
        child: Text(context.l10n.serverClearCacheBody),
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _clearingCache = true);
    final cleared = await clearServerDnsCache();
    if (!mounted) {
      return;
    }
    setState(() => _clearingCache = false);
    // Only two causes: the service is not running (nothing to clear) or the engine threw.
    // Both mean "not cleared", so the hint is actionable rather than "not wired yet".
    showServerHint(context, cleared ? context.l10n.serverCacheCleared : context.l10n.serverCacheClearFailed);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(legacySettingsProvider);
    final port = ref.watch(serverPortProvider);
    final cacheEnabled = settings.serverCacheEnabled;
    final adBlockEnabled = settings.serverAdBlockEnabled;
    final cacheSummary = cacheEnabled
        ? context.l10n.serverCacheOn(
            _cachePresetLabel(settings.serverCachePresetRaw, context.l10n),
          )
        : context.l10n.serverCacheOff;
    return CommonScaffold(
      title: context.l10n.serverModeSettings,
      body: PageBody(
        children: [
          generateSection(
            title: context.l10n.serverProxySettings,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.memory,
                title: context.l10n.serverCacheSettings,
                subtitle: cacheSummary,
                // Server-mode cache keys live in `diting_dns_mode_prefs`, a different set
                // from the normal-mode cache page, so this entry only navigates.
                onPressed: () => context.push(HubPaths.cache),
              ),
              NavEntryRow(
                glyph: AppGlyphs.rules,
                title: context.l10n.serverRuleControl,
                subtitle: adBlockEnabled
                    ? context.l10n.serverRuleControlOn
                    : context.l10n.serverRuleControlOff,
                onPressed: () => context.push(HubPaths.ruleControl),
              ),
              ListItem(
                title: Text(context.l10n.serverListenPort),
                subtitle: Text(context.l10n.serverListenPortBody),
                leading: const GlyphIcon(AppGlyphs.speed),
                trailing: Text(
                  '$port',
                  style: context.listSubtitleStyle.copyWith(
                    fontFamily: appMonospaceFontFamily,
                  ),
                ),
                onTap: () => editServerPort(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 6),
          generateSection(
            title: context.l10n.serverRuleManagement,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.block,
                title: context.l10n.serverBlocklist,
                subtitle: context.l10n.serverBlocklistBody,
                onPressed: () => context.push(Routes.rulesOf('block')),
              ),
              NavEntryRow(
                glyph: AppGlyphs.verified,
                title: context.l10n.serverAllowlist,
                subtitle: context.l10n.serverAllowlistBody,
                onPressed: () => context.push(Routes.rulesOf('allow')),
              ),
              NavEntryRow(
                glyph: AppGlyphs.dns,
                title: context.l10n.serverHosts,
                subtitle: context.l10n.serverHostsBody,
                // The legacy `REWRITELIST_MANAGEMENT` is the rewrite table; of the three
                // rule kinds here it maps to `rewrite`.
                onPressed: () => context.push(Routes.rulesOf('rewrite')),
              ),
            ],
            footer: context.l10n.serverRulesFooter,
          ),
          const SizedBox(height: 6),
          generateSection(
            title: context.l10n.serverDataReset,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.broom,
                title: context.l10n.serverClearCache,
                subtitle: context.l10n.serverClearCacheBody,
                busy: _clearingCache,
                onPressed: _clearingCache ? null : _clearCache,
              ),
              NavEntryRow(
                glyph: AppGlyphs.reset,
                title: context.l10n.serverResetStats,
                subtitle: context.l10n.serverResetStatsBody,
                onPressed: () => confirmResetServerStats(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 6),
          generateSection(
            title: context.l10n.serverBackground,
            items: [_batteryRow(context)],
            footer:
                context.l10n.serverBackgroundBody,
          ),
          const SizedBox(height: 6),
          generateSection(
            title: context.l10n.serverRunMode,
            items: [
              NavEntryRow(
                glyph: AppGlyphs.info,
                title: context.l10n.serverWizard,
                subtitle: context.l10n.serverWizardBody,
                onPressed: () => context.push(Routes.modeOnboarding),
              ),
              NavEntryRow(
                glyph: AppGlyphs.sliders,
                title: context.l10n.serverReselectMode,
                subtitle: context.l10n.serverReselectModeBody,
                onPressed: () => context.push(Routes.modeSelect),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Battery optimization: tappable while not granted, greyed out once granted. A missing
  /// channel also greys it out but must say "unavailable on this device".
  Widget _batteryRow(BuildContext context) {
    final colorScheme = context.colorScheme;
    final (subtitle, value, enabled) = switch (_battery) {
      BatteryOptimizationState.ignored => (context.l10n.serverBatteryIgnored, context.l10n.serverBatteryIgnoredShort, false),
      BatteryOptimizationState.notIgnored => (context.l10n.serverBatteryKeepAlive, null, true),
      BatteryOptimizationState.unavailable => (context.l10n.serverUnavailable, null, false),
    };
    return ListItem(
      title: Text(context.l10n.serverIgnoreBattery),
      subtitle: Text(subtitle),
      leading: GlyphIcon(
        AppGlyphs.bolt,
        color: enabled ? null : colorScheme.onSurface.withValues(alpha: 0.4),
      ),
      trailing: !_batteryLoaded
          ? const CommonCircleLoading(size: 18)
          : value == null
          ? null
          : Text(
              value,
              style: context.listCaptionStyle.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
      onTap: enabled ? _requestBattery : null,
    );
  }

  static String _cachePresetLabel(String raw, AppL10n l10n) => switch (raw) {
    'conservative' => l10n.serverCachePresetConservative,
    'high_hit_rate' => l10n.serverCachePresetHighHit,
    _ => l10n.serverCachePresetStandard,
  };
}
