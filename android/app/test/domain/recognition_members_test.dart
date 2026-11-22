import 'dart:io';

import 'package:diting_android/data/db/rust_recognition_core.dart';
import 'package:diting_android/data/recognition/recognition_members.dart';
import 'package:diting_android/data/recognition/recognition_plan.dart';
import 'package:diting_android/data/recognition/recognition_repository.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('名单解析', _recognitionMembers);
}

void _recognitionMembers() {
  group('内核目录', () {
    test('缓存键、上限与头像取舍都来自 Rust', () {
      final plan = RecognitionPlan.instance;
      expect(plan.container, 'recognition_members');
      expect(plan.configKey, 'config_json');
      expect(plan.savedAtKey, 'saved_at_ms');
      expect(plan.maxConfigBytes, 256 * 1024);
      expect(plan.maxAvatarBytes, 1024 * 1024);
      final core = RustRecognitionCore.instance;
      expect(core.avatarAccepted(0), isFalse);
      expect(core.avatarAccepted(1), isTrue);
      expect(core.avatarAccepted(plan.maxAvatarBytes), isTrue);
      expect(core.avatarAccepted(plan.maxAvatarBytes + 1), isFalse);
    });

    test('本地缓存走同一份校验，坏缓存不覆盖页面', () {
      const raw = '{"version":3,"sponsors":[{"name":"a"}]}';
      final store = MemoryLegacyPrefsStore({
        'recognition_members': {'config_json': raw},
      });
      final repository = RecognitionMembersRepository(store: store);
      expect(repository.loadCached()!.version, 3);
      store.putString('recognition_members', 'config_json', 'not json');
      expect(repository.loadCached(), isNull);
    });
  });

  group('parseRecognitionMembers', () {
    test('缺版本号 / 缺数组都视为配置无效', () {
      expect(
        () => parseRecognitionMembers('{"sponsors":[]}'),
        throwsFormatException,
      );
      expect(
        () => parseRecognitionMembers('{"version":1}'),
        throwsFormatException,
      );
    });

    test('空名称与重复名称被拒绝', () {
      expect(
        () => parseRecognitionMembers(
          '{"version":1,"sponsors":[{"name":"   "}]}',
        ),
        throwsFormatException,
      );
      expect(
        () => parseRecognitionMembers(
          '{"version":1,"sponsors":[{"name":"a"},{"name":"a"}]}',
        ),
        throwsFormatException,
      );
    });

    test('非法或重复的头像文件名被拒绝', () {
      expect(
        () => parseRecognitionMembers(
          '{"version":1,"sponsors":[{"name":"a","avatarFileName":"A.png"}]}',
        ),
        throwsFormatException,
      );
      expect(
        () => parseRecognitionMembers(
          '{"version":1,"sponsors":[{"name":"a","avatarFileName":"x_avatar.jpg"},'
          '{"name":"b","avatarFileName":"x_avatar.jpg"}]}',
        ),
        throwsFormatException,
      );
    });

    test('赞助次数缺省为 1，大于 1 的值透传到模型', () {
      final members = parseRecognitionMembers(
        '{"version":3,"sponsors":[{"name":"a"},{"name":"healer","count":2}]}',
      );
      expect(members.sponsors[0].count, 1);
      expect(members.sponsors[1].count, 2);
    });

    test('头像框只有内核认可的取值，缺省为无', () {
      final members = parseRecognitionMembers(
        '{"version":1,"sponsors":[{"name":"a"},'
        '{"name":"healer","frame":"rainbow"}]}',
      );
      expect(members.sponsors[0].frame, isNull);
      expect(members.sponsors[1].frame, RecognitionAvatarFrame.rainbow);
      expect(
        () => parseRecognitionMembers(
          '{"version":1,"sponsors":[{"name":"a","frame":"gold"}]}',
        ),
        throwsFormatException,
      );
    });

    test('仓库根目录的那份名单可以被解析', () {
      final raw = File('../../recognition_members.json').readAsStringSync();
      final members = parseRecognitionMembers(raw);
      expect(members.sponsors.length, greaterThan(5));
      expect(members.sponsors.every((m) => m.name.isNotEmpty), isTrue);
      expect(members.sponsors.firstWhere((m) => m.name == 'healer').count, 4);
      expect(
        members.sponsors.firstWhere((m) => m.name == 'healer').frame,
        RecognitionAvatarFrame.rainbow,
      );
    });
  });
}
