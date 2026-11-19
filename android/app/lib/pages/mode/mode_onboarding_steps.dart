part of 'mode_onboarding_page.dart';

/// Step 1: confirm the work mode. Display only, since the mode was already chosen.
class _ChooseModeStep extends StatelessWidget {
  const _ChooseModeStep({required this.mode});

  final AppWorkMode mode;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      glyph: _glyphOf(mode),
      title: context.l10n.onboardingChosen(mode.title(context.l10n)),
      description: mode.summary(context.l10n),
      children: [
        _TipCard(
          glyph: AppGlyphs.info,
          title: context.l10n.onboardingChangeable,
          detail: context.l10n.onboardingChangeableBody,
        ),
        _TipCard(
          glyph: AppGlyphs.layers,
          title: context.l10n.onboardingSharedRules,
          detail: context.l10n.onboardingSharedRulesBody,
        ),
        _TipCard(
          glyph: AppGlyphs.swap,
          title: context.l10n.onboardingExclusive,
          detail: context.l10n.onboardingExclusiveBody,
        ),
      ],
    );
  }

  static Glyph _glyphOf(AppWorkMode mode) => switch (mode) {
    AppWorkMode.normal => AppGlyphs.layers,
    AppWorkMode.express => AppGlyphs.bolt,
    AppWorkMode.server => AppGlyphs.dns,
  };
}

typedef _PermissionSpec = ({
  AppPermission permission,
  Glyph glyph,
  String name,
  String level,
  String detail,
});

_PermissionSpec _vpnPermission(AppL10n l10n, String detail) => (
  permission: AppPermission.vpn,
  glyph: AppGlyphs.vpn,
  name: l10n.permVpn,
  level: l10n.permRequired,
  detail: detail,
);

_PermissionSpec _notificationPermission(AppL10n l10n) => (
  permission: AppPermission.notification,
  glyph: AppGlyphs.info,
  name: l10n.permNotification,
  level: l10n.permRequired,
  detail: l10n.permNotificationBody,
);

_PermissionSpec _appListPermission(AppL10n l10n) => (
  permission: AppPermission.appList,
  glyph: AppGlyphs.appsList,
  name: l10n.permAppList,
  level: l10n.permOptional,
  detail: l10n.permAppListBody,
);

_PermissionSpec _batteryPermission(AppL10n l10n, String detail) => (
  permission: AppPermission.batteryOptimization,
  glyph: AppGlyphs.bolt,
  name: l10n.permBattery,
  level: l10n.permOptional,
  detail: detail,
);

/// Step 2: request the permissions this mode needs. Every row is a real request: `VPN 连接` opens
/// the system consent dialog, `通知` the runtime permission (or the notification settings screen
/// below Android 13), `忽略电池优化` the allowlist dialog, and `应用列表` the vendor permission with a
/// settings fallback. Denial consequences are spelled out, since the service degrades silently.
class _PermissionStep extends ConsumerWidget {
  const _PermissionStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final mode = ref.watch(workModeProvider);
    final permissions = switch (mode) {
      AppWorkMode.normal => [
        _vpnPermission(l10n, l10n.permVpnNormalBody),
        _notificationPermission(l10n),
        _appListPermission(l10n),
        _batteryPermission(l10n, l10n.permBatteryBody),
      ],
      AppWorkMode.express => [
        _vpnPermission(l10n, l10n.permVpnExpressBody),
        _notificationPermission(l10n),
        _batteryPermission(l10n, l10n.permBatteryBody),
      ],
      AppWorkMode.server => [
        _notificationPermission(l10n),
        _batteryPermission(l10n, l10n.permBatteryBody),
      ],
    };
    final snapshot = ref.watch(permissionStatesProvider).value;
    final grantedCount = permissions
        .where((spec) => snapshot?.of(spec.permission) == true)
        .length;
    return _StepScaffold(
      glyph: AppGlyphs.lock,
      title: l10n.permNeeded,
      description: snapshot == null
          ? l10n.permAllLocal
          : l10n.permGrantedCount('$grantedCount', '${permissions.length}'),
      children: [
        for (final spec in permissions)
          _PermissionRow(
            permission: spec.permission,
            glyph: spec.glyph,
            name: spec.name,
            level: spec.level,
            detail: spec.detail,
          ),
      ],
    );
  }
}

class _FinishStep extends StatelessWidget {
  const _FinishStep({required this.mode});

  final AppWorkMode mode;

  @override
  Widget build(BuildContext context) {
    final tips = switch (mode) {
      AppWorkMode.normal => [
        context.l10n.onboardingTipNormal1,
        context.l10n.onboardingTipNormal2,
        context.l10n.onboardingTipNormal3,
      ],
      AppWorkMode.express => [
        context.l10n.onboardingTipExpress1,
        context.l10n.onboardingTipExpress2,
        context.l10n.onboardingTipExpress3,
      ],
      AppWorkMode.server => [
        context.l10n.onboardingTipServer1,
        context.l10n.onboardingTipServer2,
        context.l10n.onboardingTipServer3,
      ],
    };
    return _StepScaffold(
      glyph: AppGlyphs.checkCircle,
      title: context.l10n.onboardingReady,
      description: context.l10n.onboardingReadyBody,
      children: [
        for (final (index, tip) in tips.indexed)
          _TipCard(
            glyph: AppGlyphs.check,
            title: context.l10n.onboardingTipIndex('${index + 1}'),
            detail: tip,
          ),
      ],
    );
  }
}
