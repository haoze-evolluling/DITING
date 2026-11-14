/// U5 / U6 state: the report cards and connection map derived from the live flow snapshot.
library;

import 'package:diting_android/data/network/app_insights.dart';
import 'package:diting_android/state/flow_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// U5 应用报告卡, derived from [flowViewProvider].
final appReportsProvider = Provider<List<AppReport>>(
  (ref) => buildAppReports(ref.watch(flowViewProvider).rows),
);

/// U6 连接地图, derived from [flowViewProvider].
final connectionMapProvider = Provider<List<AppConnectionGroup>>(
  (ref) => buildConnectionMap(ref.watch(flowViewProvider).rows),
);
