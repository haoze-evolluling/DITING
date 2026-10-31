import 'package:diting/desktop/pages/module_page.dart';
import 'package:diting/desktop/pages/overview_page.dart';
import 'package:diting/desktop/pages/settings_page.dart';
import 'package:diting/desktop/shell/desktop_shell.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum DesktopSection {
  overview('/overview', '总览', '运行状态与实时遥测', Icons.space_dashboard_outlined),
  resolution('/resolution', '解析', '上游调度、缓存加速与地址重写', Icons.dns_outlined),
  protection('/protection', '防护', '规则订阅与网络安全策略', Icons.shield_outlined),
  devices('/devices', '设备', '网卡、局域网与终端管理', Icons.devices_outlined),
  settings('/settings', '设置', '外观、核心服务与故障恢复', Icons.tune_outlined);

  const DesktopSection(this.path, this.label, this.description, this.icon);

  final String path;
  final String label;
  final String description;
  final IconData icon;

  static DesktopSection fromPath(String path) => values.firstWhere(
    (section) => section.path == path,
    orElse: () => DesktopSection.overview,
  );
}

GoRouter createDesktopRouter({String? initialLocation}) => GoRouter(
  initialLocation: initialLocation ?? DesktopSection.overview.path,
  routes: [
    ShellRoute(
      builder: (context, state, child) => DesktopShell(child: child),
      routes: [
        _route(
          DesktopSection.overview,
          (context, state) => const OverviewPage(),
        ),
        _route(
          DesktopSection.resolution,
          (context, state) =>
              const ModulePage(section: DesktopSection.resolution),
        ),
        _route(
          DesktopSection.protection,
          (context, state) =>
              const ModulePage(section: DesktopSection.protection),
        ),
        _route(
          DesktopSection.devices,
          (context, state) => const ModulePage(section: DesktopSection.devices),
        ),
        _route(
          DesktopSection.settings,
          (context, state) => const SettingsPage(),
        ),
      ],
    ),
  ],
);

GoRoute _route(
  DesktopSection section,
  Widget Function(BuildContext, GoRouterState) builder,
) => GoRoute(
  path: section.path,
  pageBuilder: (context, state) =>
      NoTransitionPage(key: state.pageKey, child: builder(context, state)),
);
