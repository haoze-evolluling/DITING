/// Barrel for the per-domain route tables. Conventions: sub pages set `parentNavigatorKey:
/// rootNavigatorKey`; routes use `pageBuilder: androidDefaultPage(...)`; path literals live in a
/// per-domain `XxxPaths` class; a new domain adds `lib/routes/<domain>_routes.dart` and spreads it.
library;

export 'config_routes.dart';
export 'dashboard_routes.dart';
export 'home_detail_routes.dart';
export 'hub_routes.dart';
export 'logs_routes.dart';
export 'observability_routes.dart';
export 'package:diting_shared/routes/page.dart';
export 'system_routes.dart';
