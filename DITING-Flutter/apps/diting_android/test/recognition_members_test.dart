// Guards the shipped recognition member list: bad entries must void the whole file.

import 'dart:io';

import 'package:diting_android/data/recognition/recognition_members.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('名单解析', _recognitionMembers);
}

/// Guards list parsing: duplicate names, bad avatar names and missing fields must void the file
void _recognitionMembers() {
  group('parseRecognitionMembers', () {
    test('缺版本号 / 缺数组都视为配置无效', () {
      expect(
        () => parseRecognitionMembers('{"sponsors":[],"coBuilders":[]}'),
        throwsFormatException,
      );
      expect(
        () => parseRecognitionMembers('{"version":1,"sponsors":[]}'),
        throwsFormatException,
      );
    });

    test('空名称与重复名称被拒绝', () {
      expect(
        () => parseRecognitionMembers(
          '{"version":1,"sponsors":[{"name":"   "}],"coBuilders":[]}',
        ),
        throwsFormatException,
      );
      expect(
        () => parseRecognitionMembers(
          '{"version":1,"sponsors":[{"name":"a"},{"name":"a"}],"coBuilders":[]}',
        ),
        throwsFormatException,
      );
    });

    test('非法或重复的头像文件名被拒绝', () {
      expect(
        () => parseRecognitionMembers(
          '{"version":1,"sponsors":[{"name":"a","avatarFileName":"A.png"}],'
          '"coBuilders":[]}',
        ),
        throwsFormatException,
      );
      expect(
        () => parseRecognitionMembers(
          '{"version":1,"sponsors":[{"name":"a","avatarFileName":"x_avatar.jpg"},'
          '{"name":"b","avatarFileName":"x_avatar.jpg"}],"coBuilders":[]}',
        ),
        throwsFormatException,
      );
    });

    test('仓库根目录的那份名单可以被解析', () {
      // This file is pushed to GitHub: a parse failure downgrades every client
      final raw = File('../../../recognition_members.json').readAsStringSync();
      final members = parseRecognitionMembers(raw);
      expect(members.sponsors.length, greaterThan(5));
      expect(members.coBuilders.length, greaterThan(5));
      expect(members.sponsors.every((m) => m.name.isNotEmpty), isTrue);
    });
  });
}
