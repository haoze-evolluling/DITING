/// Active primary provider plus shared relative-time labels, so the status and speed-test cards
/// cannot disagree.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selected one in single mode, otherwise the first of the race set in catalog order; null when
/// absent.
final primaryProviderProvider = Provider<MockProvider?>((ref) {
  final mode = ref.watch(workModeProvider);
  final catalog = ref.watch(dnsProviderCatalogProvider);
  final selectedId = ref.watch(selectedProviderProvider);
  final raceIds = ref.watch(raceProvidersProvider);
  final primaryId = mode == AppWorkMode.normal || mode == AppWorkMode.express
      ? selectedId
      : catalog
            .where((provider) => raceIds.contains(provider.id))
            .firstOrNull
            ?.id;
  return catalog.where((provider) => provider.id == primaryId).firstOrNull;
});

/// Relative time from the real timestamp; without one, "not tested yet".
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
