/// Network-profile state (N1): the current context, the configured network profiles and the
/// resolved effective profile.
library;

import 'package:diting_android/data/db/automation_models.dart';
import 'package:diting_android/data/db/automation_repository.dart';
import 'package:diting_android/data/db/rust_netprofile_core.dart';
import 'package:diting_android/data/native/network_context_bridge.dart';
import 'package:diting_android/state/automation_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final networkContextBridgeProvider = Provider<NetworkContextBridge>(
  (ref) => const NetworkContextBridge(),
);

final netprofileCoreProvider = Provider<RustNetprofileCore>(
  (ref) => RustNetprofileCore.instance,
);

/// The live network context (Kotlin normalization of `ConnectivityManager`).
final networkContextProvider = FutureProvider<Map<String, Object?>>(
  (ref) => ref.read(networkContextBridgeProvider).context(),
);

/// The configured network profiles, stored in `automation_profile` with `payload.kind == network`.
final networkProfilesProvider = FutureProvider<List<AutomationProfile>>((ref) async {
  ref.watch(automationRevisionProvider);
  final db = await ref.read(automationDatabaseProvider.future);
  if (db == null) return const [];
  final all = await AutomationRepository(db).profiles();
  return [
    for (final profile in all)
      if ((profile.payload['kind'] as String?) == 'network') profile,
  ];
});

/// The effective profile for the current context, resolved by `diting-netprofile-core`.
final networkProfileResolutionProvider =
    FutureProvider<Map<String, Object?>>((ref) async {
      final context = await ref.watch(networkContextProvider.future);
      final profiles = await ref.watch(networkProfilesProvider.future);
      final documents = [for (final profile in profiles) networkProfileDoc(profile)];
      try {
        return ref
            .read(netprofileCoreProvider)
            .resolve(networkCtx: context, profiles: documents);
      } catch (error) {
        return {
          'matched': false,
          'profileId': '',
          'reason': 'netprofile 内核不可用：$error',
        };
      }
    });

/// Maps a stored profile to the document `diting-netprofile-core` consumes.
Map<String, Object?> networkProfileDoc(AutomationProfile profile) {
  final payload = profile.payload;
  return {
    'id': profile.id,
    'name': profile.name,
    'priority': (payload['priority'] as num?)?.toInt() ?? 100,
    'enabled': payload['enabled'] != false,
    'networkMatch': payload['networkMatch'] ?? const {},
    'upstreamSet': (payload['upstreamSet'] as String?) ?? '',
    'ruleGroupStates': payload['ruleGroupStates'] ?? const [],
    'featureToggles': payload['featureToggles'] ?? const {},
  };
}
