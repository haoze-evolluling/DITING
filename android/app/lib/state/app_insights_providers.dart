library;

import 'package:diting_android/data/network/app_insights.dart';
import 'package:diting_android/state/flow_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appReportsProvider = Provider<List<AppReport>>(
  (ref) => buildAppReports(ref.watch(flowViewProvider).rows),
);

final connectionMapProvider = Provider<List<AppConnectionGroup>>(
  (ref) => buildConnectionMap(ref.watch(flowViewProvider).rows),
);
