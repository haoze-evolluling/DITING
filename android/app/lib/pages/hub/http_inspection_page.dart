import 'dart:async';

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/native/apps_bridge.dart';
import 'package:diting_android/data/native/ca_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_android/pages/hub/http_inspection_bypass_dialog.dart';
import 'package:diting_android/router.dart';
import 'package:diting_android/routes/standalone_routes.dart';
import 'package:diting_android/state/ca_inspection_providers.dart';
import 'package:diting_android/state/installed_apps_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_android/widgets/app_icon_avatar.dart';
import 'package:diting_android/widgets/app_list_error_state.dart';
import 'package:diting_android/widgets/app_list_view.dart';
import 'package:diting_android/widgets/section_slivers.dart';
import 'package:diting_android/widgets/page_intro.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

part 'http_inspection_apps_page.dart';

/// HTTPS inspection (upstream `HttpInspectionSettingsScreen`). Switch and app list live in
/// `http_inspection_enabled` / `http_inspection_app_packages`; CA readiness comes from
/// `CaCertificateService`.
class HttpInspectionPage extends ConsumerWidget {
  const HttpInspectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(legacySettingsProvider);
    final caAsync = ref.watch(caCertificateStateProvider);
    final ca = caAsync.value;
    final caReady = ca?.ready ?? false;
    final apps = settings.httpInspectionPackages;
    final enabled = caReady && settings.httpInspectionEnabled;
    final urlRules = enabled && settings.addressRulesEnabled;
    final http3 = enabled && settings.http3InspectionEnabled;
    final encryptedDns = enabled && settings.encryptedDnsBlockingEnabled;
    final bypass = settings.httpsBypassRules;
    final caHint = _caHint(context, ca, caReady, apps.length);
    return CommonScaffold(
      title: context.l10n.hubHttpsInspection,
      body: SliverPageBody(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                generateSection(
                  title: context.l10n.httpInspScopeSection,
                  items: [
                    ListItem.toggle(
                      leading: const GlyphIcon(AppGlyphs.lock),
                      title: Text(context.l10n.httpInspEnable),
                      subtitle: Text(caHint),
                      value: enabled,
                      onChanged: caReady
                          ? (value) =>
                                _setEnabled(context, ref, settings, value)
                          : (_) => _explainCaMissing(context, ca),
                    ),
                    ListItem(
                      leading: const GlyphIcon(AppGlyphs.appsList),
                      title: Text(context.l10n.httpInspTargetApps),
                      subtitle: Text(
                        _appsHint(context, caReady, caHint, apps.length),
                      ),
                      // A dead row reads as "the app is broken"; explain the missing certificate
                      // instead and offer the one screen that fixes it.
                      onTap: caReady
                          ? () => context.push('/hub/https-inspection/apps')
                          : () => _explainCaMissing(context, ca),
                    ),
                    ListItem(
                      leading: const GlyphIcon(AppGlyphs.verified),
                      title: Text(context.l10n.httpInspCaCert),
                      subtitle: Text(_caCertHint(context, ca, caReady)),
                      onTap: () => context.push('/hub/https-inspection/ca'),
                    ),
                  ],
                ),
                generateSection(
                  title: context.l10n.httpInspContentSection,
                  items: [
                    ListItem.toggle(
                      leading: const GlyphIcon(AppGlyphs.target),
                      title: Text(context.l10n.httpInspUrlRules),
                      subtitle: Text(
                        _urlRulesHint(
                          context,
                          caReady: caReady,
                          caHint: caHint,
                          enabled: enabled,
                          urlRules: urlRules,
                        ),
                      ),
                      value: urlRules,
                      onChanged: enabled
                          ? (value) =>
                                _setToggles(ref, settings, addressRules: value)
                          : null,
                    ),
                  ],
                ),
                generateSection(
                  title: context.l10n.httpInspProtocolSection,
                  items: [
                    ListItem.toggle(
                      leading: const GlyphIcon(AppGlyphs.bolt),
                      title: Text(context.l10n.httpInspBlockHttp3),
                      subtitle: Text(
                        !enabled
                            ? context.l10n.httpInspNeedEnable
                            : context.l10n.httpInspBlockHttp3Subtitle,
                      ),
                      value: http3,
                      onChanged: enabled
                          ? (value) => _setToggles(ref, settings, http3: value)
                          : null,
                    ),
                    ListItem.toggle(
                      leading: const GlyphIcon(AppGlyphs.lock),
                      title: Text(context.l10n.httpInspBlockDot),
                      subtitle: Text(
                        !enabled
                            ? context.l10n.httpInspNeedEnable
                            : context.l10n.httpInspBlockDotSubtitle,
                      ),
                      value: encryptedDns,
                      onChanged: enabled
                          ? (value) =>
                                _setToggles(ref, settings, encryptedDns: value)
                          : null,
                    ),
                    ListItem(
                      leading: const GlyphIcon(AppGlyphs.logs),
                      title: Text(context.l10n.httpInspRequestLogs),
                      subtitle: Text(context.l10n.httpInspRequestLogsSubtitle),
                      onTap: () {
                        if (!pushStandalone(context, '/logs')) {
                          openLocation(context, '/logs');
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          ..._bypassSlivers(context, ref, settings, bypass),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  /// Bypass suffixes are user-maintained and grow without bound; a lazy sliver keeps the first
  /// frame flat no matter how many are configured.
  List<Widget> _bypassSlivers(
    BuildContext context,
    WidgetRef ref,
    LegacySettings settings,
    Set<String> bypass,
  ) {
    final actions = [
      IconButtonData(
        glyph: AppGlyphs.add,
        tooltip: context.l10n.bypassAddTitle,
        onPressed: () => _addBypass(context, ref, settings, bypass),
      ),
    ];
    final footer = context.l10n.httpInspBypassFooter;
    if (bypass.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: generateSection(
            title: context.l10n.httpInspBypassTitle(0),
            actions: actions,
            items: [
              ListItem(
                leading: GlyphIcon(AppGlyphs.info),
                title: Text(context.l10n.httpInspBypassEmpty),
                subtitle: Text(context.l10n.httpInspBypassEmptySubtitle),
              ),
            ],
          ),
        ),
      ];
    }
    final sorted = bypass.toList()..sort();
    return lazySectionSlivers(
      title: context.l10n.httpInspBypassTitle(sorted.length),
      actions: actions,
      itemCount: sorted.length,
      footer: footer,
      itemBuilder: (context, index) {
        final rule = sorted[index];
        return ListItem(
          leading: const GlyphIcon(AppGlyphs.split, size: 20),
          title: Text(rule, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(context.l10n.httpInspBypassRowSubtitle),
          trailing: IconButton(
            tooltip: context.l10n.commonDelete,
            onPressed: () {
              settings.setHttpsBypassRules({...bypass}..remove(rule));
              _bump(ref);
            },
            icon: const GlyphIcon(AppGlyphs.delete, size: 20),
          ),
        );
      },
    );
  }

  /// Tapping a gated row while the CA is unready used to do nothing at all.
  static Future<void> _explainCaMissing(
    BuildContext context,
    CaCertificateState? state,
  ) async {
    final opened = await showFloatingDialog<bool>(
      context: context,
      child: CommonDialog(
        title: context.l10n.httpInspCaRequiredTitle,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonLater),
          ),
          if (state != null)
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.httpInspGoInstall),
            ),
        ],
        child: Text(
          state == null
              ? context.l10n.httpInspCaReadingBody
              : context.l10n.httpInspCaRequiredBody(
                  _caProblem(context.l10n, state.available, state.installed),
                ),
        ),
      ),
    );
    if (opened == true && context.mounted) {
      context.push('/hub/https-inspection/ca');
    }
  }

  /// One-line CA status shown under the master switch and the app row.
  static String _caHint(
    BuildContext context,
    CaCertificateState? ca,
    bool caReady,
    int appCount,
  ) {
    if (!caReady) {
      return ca == null
          ? context.l10n.httpInspCheckingCa
          : _caProblem(context.l10n, ca.available, ca.installed);
    }
    return appCount == 0
        ? context.l10n.httpInspNoAppsHint
        : context.l10n.httpInspSelectedHint(appCount);
  }

  static String _appsHint(
    BuildContext context,
    bool caReady,
    String caHint,
    int appCount,
  ) {
    if (!caReady) {
      return caHint;
    }
    return appCount == 0
        ? context.l10n.httpInspNoApps
        : context.l10n.httpInspSelectedApps(appCount);
  }

  static String _caCertHint(
    BuildContext context,
    CaCertificateState? ca,
    bool caReady,
  ) {
    if (ca == null) {
      return context.l10n.httpInspCheckingCa;
    }
    if (caReady) {
      return context.l10n.httpInspCaReady;
    }
    return _caProblem(context.l10n, ca.available, ca.installed);
  }

  static String _urlRulesHint(
    BuildContext context, {
    required bool caReady,
    required String caHint,
    required bool enabled,
    required bool urlRules,
  }) {
    if (!caReady) {
      return caHint;
    }
    if (!enabled) {
      return context.l10n.httpInspNeedEnable;
    }
    return urlRules
        ? context.l10n.httpInspUrlOn
        : context.l10n.httpInspUrlPaused;
  }

  /// "Certificate exists but is not installed" and "not generated yet" need different copy:
  /// install it from system settings, or regenerate first.
  static String _caProblem(AppL10n l10n, bool available, bool installed) {
    if (!available) {
      return l10n.httpInspCaMissing;
    }
    if (!installed) {
      return l10n.httpInspCaNotInstalled;
    }
    return l10n.httpInspCaReadyShort;
  }

  static void _bump(WidgetRef ref) =>
      ref.read(legacySettingsRevisionProvider.notifier).bump();

  /// Writes one of the three content toggles, leaving the other two untouched.
  static void _setToggles(
    WidgetRef ref,
    LegacySettings settings, {
    bool? http3,
    bool? encryptedDns,
    bool? addressRules,
  }) {
    settings.setHttpInspectionToggles(
      http3: http3 ?? settings.http3InspectionEnabled,
      encryptedDns: encryptedDns ?? settings.encryptedDnsBlockingEnabled,
      addressRules: addressRules ?? settings.addressRulesEnabled,
    );
    _bump(ref);
  }

  /// Toggles inspection, asking first when domain rules are off: decrypting traffic with
  /// `domain_rules_enabled` off looks "on but useless", so the dialog enables both at once.
  Future<void> _setEnabled(
    BuildContext context,
    WidgetRef ref,
    LegacySettings settings,
    bool value,
  ) async {
    if (!value) {
      settings.setHttpInspectionApps(
        packages: settings.httpInspectionPackages,
        enabled: false,
      );
      _bump(ref);
      return;
    }
    if (!settings.domainRulesEnabled) {
      final confirmed = await showFloatingDialog<bool>(
        context: context,
        child: CommonDialog(
          title: context.l10n.httpInspNeedDomainRulesTitle,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.uiCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.httpInspEnableAll),
            ),
          ],
          child: Text(context.l10n.httpInspNeedDomainRulesBody),
        ),
      );
      if (confirmed != true || !context.mounted) {
        return;
      }
      settings.setDomainRulesEnabled(true);
    }
    settings.setHttpInspectionApps(
      packages: settings.httpInspectionPackages,
      enabled: true,
    );
    _bump(ref);
  }

  Future<void> _addBypass(
    BuildContext context,
    WidgetRef ref,
    LegacySettings settings,
    Set<String> current,
  ) async {
    final value = await showFloatingDialog<String>(
      context: context,
      child: const HttpInspectionBypassDialog(),
    );
    if (value == null) {
      return;
    }
    settings.setHttpsBypassRules({...current, value});
    _bump(ref);
  }
}
