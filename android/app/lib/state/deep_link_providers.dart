/// A subscription address waiting to be imported from an external `diting://` deep link.
///
/// `DitingApp` sets it from the native channel and navigates to the subscriptions page, which opens
/// the add-subscription sheet pre-filled and then clears it. Kept in a provider so the value survives
/// the navigation and reaches an already-mounted page too.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

class PendingSubscriptionImportNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String url) => state = url;

  void clear() => state = null;
}

final pendingSubscriptionImportProvider =
    NotifierProvider<PendingSubscriptionImportNotifier, String?>(
      PendingSubscriptionImportNotifier.new,
    );
