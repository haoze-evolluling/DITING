/// App version; `pubspec.yaml` is the only source, overridden in `main()` so every caller agrees.
library;

import 'package:diting_android/data/native/app_version.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Default reads `pubspec.yaml` from the working directory, which `flutter test` sets to the
/// project root.
final appVersionProvider = Provider<AppVersion>(
  (ref) => AppVersion.fromPubspec() ?? AppVersion.unknown,
);
