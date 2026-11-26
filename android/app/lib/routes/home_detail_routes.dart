library;

import 'package:diting_android/data/dashboard_models.dart';
import 'package:diting_android/pages/home/dashboard/detail/intranet_ip_detail_page.dart';
import 'package:diting_android/pages/home/dashboard/detail/memory_detail_page.dart';
import 'package:diting_android/pages/home/dashboard/detail/network_speed_detail_page.dart';
import 'package:diting_android/pages/home/dashboard/detail/site_latency_detail_page.dart';
import 'package:diting_android/pages/home/dashboard/detail/site_latency_sites_page.dart';
import 'package:diting_android/pages/home/dashboard/detail/status_detail_page.dart';
import 'package:diting_android/routes/page.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:go_router/go_router.dart';

abstract final class HomeDetailPaths {
  static const status = '/home/status';
  static const speed = '/home/speed';
  static const latency = '/home/latency';
  static const latencySites = '/home/latency/sites';
  static const memory = '/home/memory';
  static const intranetIp = '/home/intranet-ip';
}

String? homeDetailPathOf(DashboardWidget widget) => switch (widget) {
  DashboardWidget.provider || DashboardWidget.resolution => null,
  DashboardWidget.status => HomeDetailPaths.status,
  DashboardWidget.networkSpeed => HomeDetailPaths.speed,
  DashboardWidget.siteLatency => HomeDetailPaths.latency,
  DashboardWidget.memoryInfo => HomeDetailPaths.memory,
  DashboardWidget.intranetIp => HomeDetailPaths.intranetIp,
};

List<RouteBase> homeDetailRoutes() => [
  GoRoute(
    path: HomeDetailPaths.status,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const StatusDetailPage()),
  ),
  GoRoute(
    path: HomeDetailPaths.speed,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const NetworkSpeedDetailPage()),
  ),
  GoRoute(
    path: HomeDetailPaths.latency,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const SiteLatencyDetailPage()),
    routes: [
      GoRoute(
        path: 'sites',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            androidDefaultPage(state, const SiteLatencySitesPage()),
      ),
    ],
  ),
  GoRoute(
    path: HomeDetailPaths.memory,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const MemoryDetailPage()),
  ),
  GoRoute(
    path: HomeDetailPaths.intranetIp,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) =>
        androidDefaultPage(state, const IntranetIpDetailPage()),
  ),
];
