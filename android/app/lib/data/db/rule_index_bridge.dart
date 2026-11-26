library;

import 'package:diting_android/data/errors.dart';
import 'package:flutter/services.dart';

const ruleIndexChannelName = 'com.haoze.diting/rule_index';

enum RuleIndexDataset {
  normal('normal'),
  express('express');

  const RuleIndexDataset(this.wireName);

  final String wireName;
}

Future<void> refreshRuleIndexes(RuleIndexDataset dataset) async {
  try {
    await const MethodChannel(ruleIndexChannelName)
        .invokeMethod<void>('refresh', dataset.wireName);
  } on MissingPluginException {
    ignoreError();
  } on PlatformException {
    ignoreError();
  }
}
