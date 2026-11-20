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
