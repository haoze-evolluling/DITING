import 'package:diting/app/theme/colors.dart';
import 'package:diting/desktop/state/desktop_providers.dart';
import 'package:diting/desktop/widgets/desktop_components.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(desktopDashboardProvider);
    return DesktopPage(
      children: [
        const _AppearanceCard(),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            const service = _CoreServiceCard();
            const about = _AboutCard();
            if (!wide) {
              return const Column(
                children: [service, SizedBox(height: 20), about],
              );
            }
            return const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: service),
                SizedBox(width: 20),
                Expanded(flex: 2, child: about),
              ],
            );
          },
        ),
        if (state.error != null) ...[
          const SizedBox(height: 20),
          Text(
            state.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(desktopThemeModeProvider);
    final palette = ref.watch(desktopPaletteProvider);
    return DesktopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeading(
            title: '外观与主题',
            subtitle: '沿用移动端配色与明暗规范，自动适配桌面信息密度',
            icon: Icons.palette_outlined,
          ),
          const SizedBox(height: 24),
          Text('明暗模式', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          SegmentedButton<AppThemeMode>(
            segments: const [
              ButtonSegment(
                value: AppThemeMode.system,
                label: Text('跟随系统'),
                icon: Icon(Icons.brightness_auto_outlined),
              ),
              ButtonSegment(
                value: AppThemeMode.light,
                label: Text('浅色'),
                icon: Icon(Icons.light_mode_outlined),
              ),
              ButtonSegment(
                value: AppThemeMode.dark,
                label: Text('深色'),
                icon: Icon(Icons.dark_mode_outlined),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (selection) => ref
                .read(desktopThemeModeProvider.notifier)
                .select(selection.single),
          ),
          const SizedBox(height: 26),
          Text('主题色', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            '与 Android 客户端共用同一组主题色种子',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in AppPalette.values)
                _PaletteChoice(
                  palette: item,
                  selected: item == palette,
                  onSelected: () =>
                      ref.read(desktopPaletteProvider.notifier).select(item),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaletteChoice extends StatelessWidget {
  const _PaletteChoice({
    required this.palette,
    required this.selected,
    required this.onSelected,
  });

  final AppPalette palette;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: _paletteNames[palette]!,
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 48,
          height: 48,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            color: selected
                ? scheme.primaryContainer.withValues(alpha: .45)
                : Colors.transparent,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: palette.swatch,
              borderRadius: BorderRadius.circular(9),
            ),
            child: selected
                ? const Icon(Icons.check, size: 20, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}

const _paletteNames = {
  AppPalette.system: '系统蓝',
  AppPalette.purple: '紫色',
  AppPalette.blue: '蓝色',
  AppPalette.cyan: '青色',
  AppPalette.green: '绿色',
  AppPalette.orange: '橙色',
  AppPalette.red: '红色',
  AppPalette.pink: '粉色',
  AppPalette.gold: '金色',
};

class _CoreServiceCard extends ConsumerWidget {
  const _CoreServiceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(desktopDashboardProvider);
    final core = state.coreService;
    final notifier = ref.read(desktopDashboardProvider.notifier);
    return DesktopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeading(
            title: '核心服务',
            subtitle: state.nativeAvailable
                ? '直接管理现有 Windows 后台服务'
                : 'Wails 原生桥接仅在桌面客户端中可用',
            icon: Icons.settings_applications_outlined,
            trailing: StatusPill(
              label: core?.stateText ?? '未连接',
              tone: core?.running == true
                  ? StatusTone.positive
                  : StatusTone.neutral,
            ),
          ),
          if (state.nativeAvailable) ...[
            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('开机自动启动'),
              subtitle: const Text('登录 Windows 后启动谛听桌面客户端'),
              value: state.autoStart ?? false,
              onChanged: state.isActionBusy || state.autoStart == null
                  ? null
                  : (value) => _setAutoStart(context, ref, value),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (core?.installed == false)
                  FilledButton.icon(
                    onPressed: state.isActionBusy
                        ? null
                        : () => _runAction(
                            context,
                            notifier.installAndStartCoreService,
                          ),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('安装并启动'),
                  )
                else
                  FilledButton.icon(
                    onPressed: state.isActionBusy
                        ? null
                        : () => _runAction(
                            context,
                            core?.running == true
                                ? notifier.stopCoreService
                                : notifier.startCoreService,
                          ),
                    icon: Icon(
                      core?.running == true
                          ? Icons.stop_outlined
                          : Icons.play_arrow_outlined,
                    ),
                    label: Text(core?.running == true ? '停止服务' : '启动服务'),
                  ),
                OutlinedButton.icon(
                  onPressed: state.isActionBusy
                      ? null
                      : () => _runAction(context, notifier.restartCoreService),
                  icon: const Icon(Icons.restart_alt_outlined),
                  label: const Text('重新启动'),
                ),
              ],
            ),
            if (core?.message.isNotEmpty == true) ...[
              const SizedBox(height: 16),
              Text(core!.message, style: Theme.of(context).textTheme.bodySmall),
            ],
          ] else ...[
            const SizedBox(height: 20),
            Text(
              '在浏览器预览中仅展示布局与 DNS 数据，不会模拟原生服务操作。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _setAutoStart(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    try {
      await ref.read(desktopDashboardProvider.notifier).setAutoStart(value);
    } on Object catch (error) {
      if (context.mounted) _showMessage(context, error.toString());
    }
  }
}

class _AboutCard extends ConsumerWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(desktopDashboardProvider);
    final notifier = ref.read(desktopDashboardProvider.notifier);
    return DesktopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeading(
            title: '诊断与恢复',
            subtitle: '本地优先 · 不经过云端',
            icon: Icons.health_and_safety_outlined,
          ),
          const SizedBox(height: 20),
          Text(
            '应急恢复会复用现有 DNS 快照与自愈逻辑，用于修复异常退出后残留的网络接管。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: state.nativeAvailable && !state.isActionBusy
                ? () => _confirmRestore(context, notifier)
                : null,
            icon: const Icon(Icons.build_outlined),
            label: const Text('运行应急恢复'),
          ),
          const Divider(height: 32),
          _AboutRow(label: '运行平台', value: state.platform),
          const SizedBox(height: 8),
          _AboutRow(
            label: '核心版本',
            value: state.snapshot?.version.isNotEmpty == true
                ? state.snapshot!.version
                : '待连接',
          ),
          const SizedBox(height: 8),
          const _AboutRow(label: '界面框架', value: 'Flutter · Material 3'),
        ],
      ),
    );
  }

  Future<void> _confirmRestore(
    BuildContext context,
    DesktopDashboardNotifier notifier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('运行应急恢复？'),
        content: const Text('将检查 DNS 接管快照，并仅在发现残留状态时执行恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始恢复'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _runAction(context, notifier.runEmergencyRestore);
    }
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
      Text(value, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

Future<void> _runAction(
  BuildContext context,
  Future<String> Function() action,
) async {
  try {
    final message = await action();
    if (context.mounted) _showMessage(context, message);
  } on Object catch (error) {
    if (context.mounted) _showMessage(context, error.toString());
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}
