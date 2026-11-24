/// VPN 接口与 DNS 共用的 IPv6 策略。
///
/// 三态取代了旧的 `tunnelIpv6` / `dnsAaaa` 两个独立开关，避免出现
/// “返回 AAAA 但隧道没有 IPv6”这类不一致组合。
enum Ipv6Mode {
  /// 不向隧道注入 IPv6，AAAA 查询返回 NODATA。
  ipv4('ipv4'),

  /// 物理网络支持 IPv6 时才启用，否则按 [ipv4] 处理。
  auto('auto'),

  /// 物理网络支持 IPv6 时启用，并在域名存在 AAAA 时压制 A 查询。
  ipv6('ipv6');

  const Ipv6Mode(this.storageValue);

  final String storageValue;

  static Ipv6Mode? fromStorage(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null) return null;
    for (final mode in values) {
      if (mode.storageValue == value) return mode;
    }
    return null;
  }
}
