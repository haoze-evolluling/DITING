import 'package:diting/desktop/app/desktop_router.dart';
import 'package:diting/desktop/data/desktop_models.dart';
import 'package:diting/desktop/state/desktop_providers.dart';
import 'package:diting/desktop/widgets/desktop_components.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared scaffold for modules whose navigation and information hierarchy are
/// ready, but whose editing workflows have not yet been migrated.
class ModulePage extends ConsumerWidget {
  const ModulePage({super.key, required this.section});

  final DesktopSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(desktopDashboardProvider).snapshot;
    final content = _contentFor(section, snapshot);
    return DesktopPage(
      children: [
        DesktopCard(
          color: Theme.of(context).colorScheme.primaryContainer
              .withValues(alpha: .36),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  section.icon,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      content.title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      content.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SnapshotStrip(section: section, snapshot: snapshot),
        const SizedBox(height: 20),
        PendingPanel(
          icon: content.icon,
          title: '功能工作区',
          description: '页面容器与数据入口已建立，详细配置将在后续迭代中逐项接入现有 Go 接口。',
          capabilities: content.capabilities,
        ),
      ],
    );
  }

  _ModuleContent _contentFor(
    DesktopSection section,
    DesktopSnapshot? snapshot,
  ) => switch (section) {
    DesktopSection.resolution => const _ModuleContent(
      title: '让每一次解析更快、更可靠',
      description: '统一管理上游调度、智能缓存、地址重写与 IPv6 过渡能力。',
      icon: Icons.hub_outlined,
      capabilities: ['上游服务器', 'Bootstrap', '缓存策略', 'DNS 重写', 'DNS64'],
    ),
    DesktopSection.protection => const _ModuleContent(
      title: '清晰掌握每一项防护策略',
      description: '规则、拦截方式和高级安全能力将沿用移动端一致的信息层级。',
      icon: Icons.admin_panel_settings_outlined,
      capabilities: ['规则订阅', '自定义规则', '应用拦截', '规则检测', '时间计划'],
    ),
    DesktopSection.devices => const _ModuleContent(
      title: '管理网络入口与局域网设备',
      description: '集中查看网卡接管、局域网 DNS、终端分组与加密服务。',
      icon: Icons.lan_outlined,
      capabilities: ['网卡接管', '局域网 DNS', '设备分组', '加密 DNS', '访问控制'],
    ),
    _ => throw ArgumentError('Unsupported module: $section'),
  };
}

class _SnapshotStrip extends StatelessWidget {
  const _SnapshotStrip({required this.section, required this.snapshot});

  final DesktopSection section;
  final DesktopSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final items = switch (section) {
      DesktopSection.resolution => [
        ('调度方式', snapshot?.dns.modeLabel ?? '—', Icons.alt_route_outlined),
        (
          '上游节点',
          snapshot == null ? '—' : '${snapshot!.dns.upstreams.length}',
          Icons.cloud_outlined,
        ),
        (
          '缓存条目',
          snapshot?.cache == null
              ? '—'
              : formatCount(snapshot!.cache!.entryCount),
          Icons.cached_outlined,
        ),
      ],
      DesktopSection.protection => [
        (
          '有效规则',
          snapshot?.filter == null
              ? '—'
              : formatCount(snapshot!.filter!.totalRules),
          Icons.rule_outlined,
        ),
        (
          '启用订阅',
          snapshot?.filter == null ? '—' : '${snapshot!.filter!.activeLists}',
          Icons.playlist_add_check_outlined,
        ),
        (
          '累计拦截',
          snapshot?.filter == null
              ? '—'
              : formatCount(snapshot!.filter!.blockedQueries),
          Icons.block_outlined,
        ),
      ],
      DesktopSection.devices => [
        (
          '保护网卡',
          snapshot == null ? '—' : '${snapshot!.takeover.adapterCount}',
          Icons.settings_ethernet_outlined,
        ),
        (
          '局域网服务',
          snapshot == null
              ? '—'
              : snapshot!.dns.allowLan
              ? '已开放'
              : '仅本机',
          Icons.wifi_tethering_outlined,
        ),
        (
          '服务地址',
          snapshot?.dns.primaryAddress ?? '—',
          Icons.location_on_outlined,
        ),
      ],
      _ => const <(String, String, IconData)>[],
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final item in items)
              SizedBox(
                width: compact
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 28) / 3,
                child: DesktopCard(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Icon(
                        item.$3,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.$1,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.$2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ModuleContent {
  const _ModuleContent({
    required this.title,
    required this.description,
    required this.icon,
    required this.capabilities,
  });

  final String title;
  final String description;
  final IconData icon;
  final List<String> capabilities;
}
