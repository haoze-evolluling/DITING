import 'dart:io';

import 'package:diting_shared/data/db/storage_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final storageKt = _kotlinFile('core/rule/StorageContract.kt').readAsStringSync();
  final datasetKt = _kotlinFile('core/rule/RuleDataset.kt').readAsStringSync();

  test('库名常量与 Kotlin StorageContract 一致', () {
    final kotlin = _constants(storageKt);
    const expected = {
      'NORMAL_RULES': StorageContract.normalRulesDatabase,
      'NORMAL_LOGS': StorageContract.normalLogsDatabase,
      'EXPRESS_RULES': StorageContract.expressRulesDatabase,
      'EXPRESS_LOGS': StorageContract.expressLogsDatabase,
      'GLOBAL': StorageContract.globalDatabase,
    };
    for (final entry in expected.entries) {
      expect(kotlin[entry.key], entry.value, reason: entry.key);
    }
  });

  test('各模式偏好容器与 Kotlin RuleDataset 一致', () {
    final kotlin = _prefsNames(datasetKt);
    const expected = {
      'NORMAL': 'dns_vpn_prefs',
      'EXPRESS': 'diting_express_prefs',
    };
    expect(kotlin, expected);
  });
}

File _kotlinFile(String relative) {
  var directory = Directory.current;
  for (var depth = 0; depth < 6; depth++) {
    for (final prefix in const ['android/app/src', 'android/app/android/app/src']) {
      final candidate = File(
        '${directory.path}/$prefix/main/kotlin/com/haoze/diting/$relative',
      );
      if (candidate.existsSync()) return candidate;
    }
    directory = directory.parent;
  }
  throw StateError('cannot locate $relative from ${Directory.current.path}');
}

Map<String, String> _constants(String source) {
  final pattern = RegExp(r'const val ([A-Z_]+) = "([^"]*)"');
  return {
    for (final match in pattern.allMatches(source))
      match.group(1)!: match.group(2)!,
  };
}

Map<String, String> _prefsNames(String source) {
  final pattern = RegExp(r'(NORMAL|EXPRESS) -> "([^"]+)"');
  return {
    for (final match in pattern.allMatches(source))
      match.group(1)!: match.group(2)!,
  };
}
