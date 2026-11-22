library;

import 'package:diting_android/data/native/app_version.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appVersionProvider = Provider<AppVersion>(
  (ref) => AppVersion.fromPubspec() ?? AppVersion.unknown,
);
