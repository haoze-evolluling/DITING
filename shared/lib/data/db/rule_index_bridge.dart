/// Dart side of `com.haoze.diting/rule_index`: asks the platform to recompile the
/// subscription rule tries after rule writes, so the next service start can mmap them
/// instead of compiling. Mirrors the legacy app rebuilding rule caches after every batch.
/// Fire-and-forget by design: a missed refresh only costs one compile at the next start,
/// because the service re-validates the stamp against the database.
library;

import 'package:flutter/services.dart';

const ruleIndexChannelName = 'com.haoze.diting/rule_index';

enum RuleIndexDataset {
  normal('normal'),
  express('express'),
  server('server');

  const RuleIndexDataset(this.wireName);

  final String wireName;
}

Future<void> refreshRuleIndexes(RuleIndexDataset dataset) async {
  try {
    await const MethodChannel(ruleIndexChannelName)
        .invokeMethod<void>('refresh', dataset.wireName);
  } on MissingPluginException {
    // No native implementation (tests, desktop hosts): nothing to refresh.
  } on PlatformException {
    // The service recompiles on demand when the stamp is stale; surface nothing.
  }
}
