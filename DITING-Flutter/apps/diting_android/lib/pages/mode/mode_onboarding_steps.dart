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
    AppWorkMode.server => AppGlyphs.dns,
    AppWorkMode.express => AppGlyphs.bolt,
  };
}

/// Step 2: request the permissions this mode needs. Every row is a real request: `VPN 连接` opens
/// the system consent dialog, `通知` the runtime permission (or the notification settings screen
/// below Android 13), `忽略电池优化` the allowlist dialog, and `应用列表` the vendor permission with a
/// settings fallback. Denial consequences are spelled out, since the service degrades silently.
class _PermissionStep extends ConsumerWidget {
  const _PermissionStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(workModeProvider);
    final permissions = switch (mode) {
      AppWorkMode.normal => [
        (
          AppPermission.vpn,
          AppGlyphs.vpn,
          context.l10n.permVpn,
          context.l10n.permRequired,
          context.l10n.permVpnNormalBody,
        ),
        (
          AppPermission.notification,
          AppGlyphs.info,
          context.l10n.permNotification,
          context.l10n.permRequired,
          context.l10n.permNotificationBody,
        ),
        (
          AppPermission.appList,
          AppGlyphs.appsList,
          context.l10n.permAppList,
          context.l10n.permOptional,
          context.l10n.permAppListBody,
        ),
        (
          AppPermission.batteryOptimization,
          AppGlyphs.bolt,
          context.l10n.permBattery,
          context.l10n.permOptional,
          context.l10n.permBatteryBody,
        ),
      ],
      AppWorkMode.server => [
        (
          AppPermission.notification,
          AppGlyphs.info,
          context.l10n.permNotification,
          context.l10n.permRequired,
          context.l10n.permNotificationBody,
        ),
        (
          AppPermission.batteryOptimization,
          AppGlyphs.bolt,
          context.l10n.permBattery,
          context.l10n.permOptional,
          context.l10n.permBatteryServerBody,
        ),
      ],
      AppWorkMode.express => [
        (AppPermission.vpn, AppGlyphs.vpn, context.l10n.permVpn, context.l10n.permRequired, context.l10n.permVpnExpressBody),
        (
          AppPermission.notification,
          AppGlyphs.info,
          context.l10n.permNotification,
          context.l10n.permRequired,
          context.l10n.permNotificationBody,
        ),
        (
          AppPermission.batteryOptimization,
          AppGlyphs.bolt,
          context.l10n.permBattery,
          context.l10n.permOptional,
          context.l10n.permBatteryBody,
        ),
      ],
    };
    final snapshot = ref.watch(permissionStatesProvider).value;
    final grantedCount = permissions
        .where((item) => snapshot?.of(item.$1) == true)
        .length;
    return _StepScaffold(
      glyph: AppGlyphs.lock,
      title: context.l10n.permNeeded,
      description: snapshot == null
          ? context.l10n.permAllLocal
          : context.l10n.permGrantedCount(
              '$grantedCount',
              '${permissions.length}',
            ),
      children: [
        for (final (permission, glyph, name, level, detail) in permissions)
          _PermissionRow(
            permission: permission,
            glyph: glyph,
            name: name,
            level: level,
            detail: detail,
          ),
      ],
    );
  }
}

class _FinishStep extends StatelessWidget {
  _FinishStep({required this.mode});

  final AppWorkMode mode;

  @override
  Widget build(BuildContext context) {
    final tips = switch (mode) {
      AppWorkMode.normal => [
        context.l10n.onboardingTipNormal1,
        context.l10n.onboardingTipNormal2,
        context.l10n.onboardingTipNormal3,
      ],
      AppWorkMode.server => [
        context.l10n.onboardingTipServer1,
        context.l10n.onboardingTipServer2,
        context.l10n.onboardingTipServer3,
      ],
      AppWorkMode.express => [
        context.l10n.onboardingTipExpress1,
        context.l10n.onboardingTipExpress2,
        context.l10n.onboardingTipExpress3,
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
