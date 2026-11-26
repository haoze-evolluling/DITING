import 'package:diting_android/data/notifications/notification_status_text.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LegacySettings settings({
    Map<String, Object?> dns = const {},
  }) => LegacySettings(
    MemoryLegacyPrefsStore({
      'dns_vpn_prefs': dns,
    }),
  );

  group('运行中的通知正文', () {
    test('按解析模式与自定义服务商生成正文', () {
      expect(defaultRunningNotificationText(settings()), '运行中 · 阿里云');

      final race = defaultRunningNotificationText(
        settings(
          dns: const {
            'dns_resolution_mode': 'parallel_race',
            'parallel_race_provider_ids':
                '["preset_alidns_dns","preset_dnspod_dns"]',
          },
        ),
      );
      expect(race, '运行中 · [最快响应] 2 个服务商');

      final custom = defaultRunningNotificationText(
        settings(
          dns: const {
            'selected_provider_id': 'user_1',
            'user_providers_json':
                '[{"id":"user_1","name":"自建 DoH","protocol":"DOH",'
                '"url":"https://dns.example.com/query","host":"","port":853}]',
          },
        ),
      );
      expect(custom, '运行中 · 自建 DoH');
    });
  });
}
