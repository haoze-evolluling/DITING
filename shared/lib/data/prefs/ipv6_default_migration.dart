import 'ipv6_mode.dart';
import 'legacy_prefs_store.dart';
import 'legacy_settings.dart';

const _lastIpv6ModeKey = 'last_ipv6_mode';
const _lastTunnelIpv6Key = 'last_tunnel_ipv6';
const _lastDnsAaaaKey = 'last_dns_aaaa';

/// 把 IPv6 策略的默认值从“自动”改为“仅 IPv4”，并迁移升级前采用“自动”的用户。
///
/// 普通模式与简洁模式各有独立的设置容器和上次启动参数容器，因此都需处理。
/// 每个设置容器只迁移一次：标记写入后，用户仍可在设置里重新选择“自动”。
void migrateIpv6DefaultToIpv4(LegacyPrefsStore store) {
  _migrateContainer(
    store,
    settingsContainer: LegacySettings.uiContainer,
    stateContainer: LegacySettings.uiContainer,
  );
  _migrateContainer(
    store,
    settingsContainer: LegacySettings.expressContainer,
    stateContainer: LegacySettings.expressRunningContainer,
  );
}

void _migrateContainer(
  LegacyPrefsStore store, {
  required String settingsContainer,
  required String stateContainer,
}) {
  final migrated = store.read(
    settingsContainer,
    LegacySettings.ipv6DefaultIpv4MigratedKey,
  );
  if (migrated == true) return;
  final settings = LegacySettings(store, dnsContainer: settingsContainer);
  if (settings.ipv6Mode != Ipv6Mode.ipv6) {
    // 同时回写旧布尔键，避免回滚到旧版本后又回到“自动”。
    settings.setIpv6Mode(Ipv6Mode.ipv4);
    _migrateLastStart(store, stateContainer);
  }
  store.putBool(
    settingsContainer,
    LegacySettings.ipv6DefaultIpv4MigratedKey,
    true,
  );
}

/// 磁贴/小组件冷启动会直接使用上次启动参数，这里同步迁移，避免绕过设置页。
void _migrateLastStart(LegacyPrefsStore store, String container) {
  final values = store.readAll(container);
  if (!values.containsKey(_lastIpv6ModeKey) &&
      !values.containsKey(_lastTunnelIpv6Key) &&
      !values.containsKey(_lastDnsAaaaKey)) {
    return;
  }
  store.putString(container, _lastIpv6ModeKey, Ipv6Mode.ipv4.storageValue);
  if (values[_lastTunnelIpv6Key] is bool) {
    store.putBool(container, _lastTunnelIpv6Key, false);
  }
  if (values[_lastDnsAaaaKey] is bool) {
    store.putBool(container, _lastDnsAaaaKey, false);
  }
}
