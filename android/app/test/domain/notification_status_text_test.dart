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
    test('单一服务显示状态与上游名', () {
      expect(defaultRunningNotificationText(settings()), '运行中 · 阿里云');
    });

    test('竞速模式显示解析模式与服务商数量', () {
      final text = defaultRunningNotificationText(
        settings(
          dns: const {
            'dns_resolution_mode': 'parallel_race',
            'parallel_race_provider_ids':
                '["preset_alidns_dns","preset_dnspod_dns"]',
          },
        ),
      );
      expect(text, '运行中 · [最快响应] 2 个服务商');
    });

    test('自定义服务商使用其名称', () {
      final text = defaultRunningNotificationText(
        settings(
          dns: const {
            'selected_provider_id': 'user_1',
            'user_providers_json':
                '[{"id":"user_1","name":"自建 DoH","protocol":"DOH",'
                '"url":"https://dns.example.com/query","host":"","port":853}]',
          },
        ),
      );
      expect(text, '运行中 · 自建 DoH');
    });
  });
}
