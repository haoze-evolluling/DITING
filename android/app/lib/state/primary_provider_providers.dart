library;

import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/state/provider_catalog_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final primaryProviderProvider = Provider<MockProvider?>((ref) {
  final catalog = ref.watch(dnsProviderCatalogProvider);
  final selectedId = ref.watch(selectedProviderProvider);
  return catalog.where((provider) => provider.id == selectedId).firstOrNull;
});

String elapsedAgoLabel(DateTime? at) {
  if (at == null) return currentL10n.siteLatencyNotTested;
  final seconds = DateTime.now().difference(at).inSeconds;
  if (seconds < 5) return currentL10n.elapsedJustNow;
  if (seconds < 60) return currentL10n.elapsedSecondsAgo(seconds);
  final minutes = seconds ~/ 60;
  if (minutes < 60) return currentL10n.elapsedMinutesAgo(minutes);
  final hours = minutes ~/ 60;
  if (hours < 24) return currentL10n.elapsedHoursAgo(hours);
  return currentL10n.elapsedDaysAgo(hours ~/ 24);
}
