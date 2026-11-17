//! Native Windows DNS configuration.
//!
//! `SetInterfaceDnsSettings` is strict: one wrong-family or non-literal address rejects the whole
//! call with ERROR_INVALID_PARAMETER, leaving the adapter untouched. The snapshot is therefore
//! normalized first, and the `netsh` path is used as a fallback because a failed restore means the
//! machine stays pinned to `127.0.0.1` and the user cannot reach the network to retry.

use std::collections::HashSet;
use std::net::{IpAddr, SocketAddr};
use std::ptr;

use windows_sys::Win32::NetworkManagement::IpHelper::{
    SetInterfaceDnsSettings, DNS_INTERFACE_SETTINGS, DNS_INTERFACE_SETTINGS_VERSION1,
    DNS_SETTING_IPV6, DNS_SETTING_NAMESERVER,
};

use diting_desktop_api::platform_types::AdapterState;

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;

use super::adapter_native::scan_adapters_native;

#[link(name = "dnsapi")]
extern "system" {
    fn DnsFlushResolverCache() -> i32;
}

/// Flushes the resolver cache natively, falling back to `ipconfig /flushdns` when the export is
/// unavailable or fails.
pub(crate) async fn flush_dns_cache(executor: &dyn CommandExecutor) -> PlatformResult<()> {
    if flush_dns_cache_native().is_ok() {
        return Ok(());
    }
    executor
        .run_checked("ipconfig", &["/flushdns"])
        .await
        .map(|_| ())
}

pub(crate) fn flush_dns_cache_native() -> PlatformResult<()> {
    // SAFETY: the export takes no arguments and merely invalidates resolver state.
    if unsafe { DnsFlushResolverCache() } == 0 {
        Err(PlatformError::message("DnsFlushResolverCache 失败"))
    } else {
        Ok(())
    }
}

/// Normalizes one DNS server literal for a specific stack.
///
/// Windows rejects `fe80::1%12` (zone), `[fe80::1]` (brackets), `8.8.8.8:53` (port), protocol
/// URLs, and cross-family entries. Returning `None` here lets the caller drop only the bad entry
/// instead of losing the entire list.
pub(crate) fn normalize_dns_address(raw: &str, is_ipv6: bool) -> (String, bool) {
    let mut text = raw.trim();
    if text.is_empty() {
        return (String::new(), false);
    }

    // `8.8.8.8:53` / `[fe80::1]:53`: let the std parser strip the port when it can.
    if let Ok(socket) = text.parse::<SocketAddr>() {
        return normalize_ip_for_stack(socket.ip(), is_ipv6);
    }
    if text.starts_with('[') {
        if let Some(end) = text.find(']') {
            text = &text[1..end];
        }
    }
    text = text.trim_matches(['[', ']']);
    if let Some(index) = text.rfind('%') {
        if index > 0 {
            text = &text[..index];
        }
    }

    match text.trim().parse::<IpAddr>() {
        Ok(ip) => normalize_ip_for_stack(ip, is_ipv6),
        Err(_) => (String::new(), false),
    }
}

fn normalize_ip_for_stack(ip: IpAddr, is_ipv6: bool) -> (String, bool) {
    if is_ipv6 {
        match ip {
            IpAddr::V6(address) => {
                // `::ffff:a.b.c.d` is IPv4-mapped and must not be sent to the IPv6 stack.
                if address.to_ipv4_mapped().is_some() {
                    (String::new(), false)
                } else {
                    (address.to_string(), true)
                }
            }
            IpAddr::V4(_) => (String::new(), false),
        }
    } else {
        match ip {
            IpAddr::V4(address) => (address.to_string(), true),
            IpAddr::V6(address) => match address.to_ipv4_mapped() {
                Some(mapped) => (mapped.to_string(), true),
                None => (String::new(), false),
            },
        }
    }
}

/// Splits a mixed list into same-family literals, deduplicated in original order. The dropped
/// entries are returned for logging; a caller that ignores them may silently lose a DNS server.
pub(crate) fn normalize_servers_for_stack(
    servers: &[String],
    is_ipv6: bool,
) -> (Vec<String>, Vec<String>) {
    let mut kept = Vec::new();
    let mut dropped = Vec::new();
    let mut seen = HashSet::new();
    for raw in servers {
        let (address, ok) = normalize_dns_address(raw, is_ipv6);
        if !ok {
            dropped.push(raw.clone());
            continue;
        }
        if seen.insert(address.clone()) {
            kept.push(address);
        }
    }
    (kept, dropped)
}

fn protocol_label(is_ipv6: bool) -> &'static str {
    if is_ipv6 {
        "IPv6"
    } else {
        "IPv4"
    }
}

fn parse_guid(guid: &str) -> Option<windows_sys::core::GUID> {
    let clean = guid.trim().trim_matches(|ch| ch == '{' || ch == '}');
    let parts: Vec<&str> = clean.split('-').collect();
    if parts.len() != 5 {
        return None;
    }
    let data1 = u32::from_str_radix(parts[0], 16).ok()?;
    let data2 = u16::from_str_radix(parts[1], 16).ok()?;
    let data3 = u16::from_str_radix(parts[2], 16).ok()?;
    if parts[3].len() != 4 || parts[4].len() != 12 {
        return None;
    }
    let mut data4 = [0u8; 8];
    for index in 0..2 {
        data4[index] = u8::from_str_radix(&parts[3][index * 2..index * 2 + 2], 16).ok()?;
    }
    for index in 0..6 {
        data4[index + 2] = u8::from_str_radix(&parts[4][index * 2..index * 2 + 2], 16).ok()?;
    }
    Some(windows_sys::core::GUID {
        data1,
        data2,
        data3,
        data4,
    })
}

/// Applies one stack's DNS list through `SetInterfaceDnsSettings`. An empty list passes a null
/// `NameServer`, which is how Windows is told to fall back to DHCP.
pub(crate) fn set_interface_dns_settings_native(
    guid_str: &str,
    is_ipv6: bool,
    servers: &[String],
) -> PlatformResult<()> {
    let Some(guid) = parse_guid(guid_str) else {
        return Err(PlatformError::message(format!(
            "无效的网卡 GUID: {guid_str}"
        )));
    };

    let mut flags = DNS_SETTING_NAMESERVER as u64;
    if is_ipv6 {
        flags |= DNS_SETTING_IPV6 as u64;
    }

    // The UTF-16 buffer must outlive the API call; `settings` only borrows its pointer.
    let mut name_server: Vec<u16> = if servers.is_empty() {
        Vec::new()
    } else {
        servers
            .join(",")
            .encode_utf16()
            .chain(std::iter::once(0))
            .collect()
    };
    let name_server_ptr = if servers.is_empty() {
        ptr::null_mut()
    } else {
        name_server.as_mut_ptr()
    };

    let settings = DNS_INTERFACE_SETTINGS {
        Version: DNS_INTERFACE_SETTINGS_VERSION1,
        Flags: flags,
        Domain: ptr::null_mut(),
        NameServer: name_server_ptr,
        SearchList: ptr::null_mut(),
        RegistrationEnabled: 0,
        RegisterAdapterName: 0,
        EnableLLMNR: 0,
        QueryAdapterName: 0,
        ProfileNameServer: ptr::null_mut(),
    };

    // SAFETY: `settings` is fully initialized and every pointer either null or points at a live
    // buffer for the duration of the call.
    let status = unsafe { SetInterfaceDnsSettings(guid, &settings) };
    if status != 0 {
        let detail = std::io::Error::from_raw_os_error(status as i32);
        return Err(PlatformError::message(format!(
            "SetInterfaceDnsSettings ({}) 失败，错误码: {status} ({detail})",
            protocol_label(is_ipv6)
        )));
    }
    Ok(())
}

async fn run_netsh(
    executor: &dyn CommandExecutor,
    family: &str,
    args: &[&str],
) -> PlatformResult<()> {
    let mut full: Vec<&str> = vec!["interface", family];
    full.extend_from_slice(args);
    let output = executor.run("netsh", &full).await?;
    if output.success {
        Ok(())
    } else {
        Err(PlatformError::message(format!(
            "netsh {} 失败: {}",
            full.join(" "),
            output.text()
        )))
    }
}

/// Replaces a stack's DNS list via `netsh`. An empty list restores DHCP.
pub(crate) async fn set_stack_dns_netsh(
    executor: &dyn CommandExecutor,
    adapter_name: &str,
    is_ipv6: bool,
    servers: &[String],
) -> PlatformResult<()> {
    let family = if is_ipv6 { "ipv6" } else { "ipv4" };
    let name = format!("name={adapter_name}");

    if servers.is_empty() {
        return run_netsh(
            executor,
            family,
            &["set", "dnsservers", &name, "source=dhcp"],
        )
        .await;
    }

    run_netsh(
        executor,
        family,
        &[
            "set",
            "dnsservers",
            &name,
            "static",
            &servers[0],
            "primary",
            "validate=no",
        ],
    )
    .await?;

    for (offset, server) in servers[1..].iter().enumerate() {
        let index = format!("index={}", offset + 2);
        run_netsh(
            executor,
            family,
            &["add", "dnsservers", &name, server, &index, "validate=no"],
        )
        .await?;
    }
    Ok(())
}

async fn reset_adapter_dns_netsh(
    executor: &dyn CommandExecutor,
    adapter_name: &str,
) -> PlatformResult<()> {
    let mut errors = Vec::new();
    for is_ipv6 in [false, true] {
        if let Err(error) = set_stack_dns_netsh(executor, adapter_name, is_ipv6, &[]).await {
            errors.push(error);
        }
    }
    join_errors(errors)
}

async fn apply_stack_dns(
    executor: &dyn CommandExecutor,
    guid: &str,
    adapter_name: &str,
    is_ipv6: bool,
    servers: &[String],
) -> PlatformResult<()> {
    let protocol = protocol_label(is_ipv6);
    let (kept, dropped) = normalize_servers_for_stack(servers, is_ipv6);
    if !dropped.is_empty() {
        eprintln!(
            "[DNS] 网卡 [{adapter_name}] 的 {protocol} 快照含 {} 条非法地址，已丢弃: {}",
            dropped.len(),
            format_servers(&dropped)
        );
    }

    match set_interface_dns_settings_native(guid, is_ipv6, &kept) {
        Ok(()) => Ok(()),
        Err(native_error) => {
            if adapter_name.is_empty() {
                return Err(PlatformError::message(format!(
                    "设置网卡 [{adapter_name}] 的 {protocol} DNS 失败（下发地址: {}）: {native_error}",
                    format_servers(&kept)
                )));
            }
            match set_stack_dns_netsh(executor, adapter_name, is_ipv6, &kept).await {
                Ok(()) => {
                    eprintln!(
                        "[DNS] 网卡 [{adapter_name}] 的 {protocol} DNS 原生 API 失败，已通过 netsh 兜底完成: {native_error}"
                    );
                    Ok(())
                }
                Err(netsh_error) => Err(PlatformError::message(format!(
                    "设置网卡 [{adapter_name}] 的 {protocol} DNS 失败（下发地址: {}）: {native_error}（netsh 兜底亦失败: {netsh_error}）",
                    format_servers(&kept)
                ))),
            }
        }
    }
}

fn format_servers(servers: &[String]) -> String {
    format!("[{}]", servers.join(" "))
}

/// Applies both stacks. `v4`/`v6` empty means that stack returns to DHCP.
pub(crate) async fn set_adapter_dns_dual_stack_native(
    executor: &dyn CommandExecutor,
    guid: &str,
    adapter_name: &str,
    v4_servers: &[String],
    v6_servers: &[String],
) -> PlatformResult<()> {
    let mut errors = Vec::new();
    if let Err(error) = apply_stack_dns(executor, guid, adapter_name, false, v4_servers).await {
        errors.push(error);
    }
    if let Err(error) = apply_stack_dns(executor, guid, adapter_name, true, v6_servers).await {
        errors.push(error);
    }
    join_errors(errors)
}

pub(crate) async fn reset_adapter_dns_native(
    executor: &dyn CommandExecutor,
    guid: &str,
    adapter_name: &str,
) -> PlatformResult<()> {
    set_adapter_dns_dual_stack_native(executor, guid, adapter_name, &[], &[]).await
}

/// Resets every adapter whose DNS still contains a loopback address. Failures are aggregated
/// because swallowing them would report a successful self-heal while the adapter stays broken.
pub(crate) async fn reset_residual_loopback_dns_native(
    executor: &dyn CommandExecutor,
) -> PlatformResult<()> {
    let adapters = scan_adapters_native()?;
    let mut errors = Vec::new();
    for adapter in adapters {
        if !adapter.has_residual_loopback {
            continue;
        }
        if let Err(error) = reset_adapter_dns_native(executor, &adapter.id, &adapter.name).await {
            errors.push(PlatformError::message(format!(
                "重置网卡 [{}] 残留 DNS 失败: {error}",
                adapter.name
            )));
        }
    }
    join_errors(errors)
}

/// Last-resort sweep: adapters that failed snapshot restoration are forced back to DHCP so the
/// machine regains connectivity. The snapshot is intentionally preserved so a later restore can
/// still write the original static servers.
pub(crate) async fn force_reset_loopback_adapters_to_dhcp(
    executor: &dyn CommandExecutor,
    adapters: &[AdapterState],
) -> PlatformResult<()> {
    if adapters.is_empty() {
        return Ok(());
    }
    let scanned = scan_adapters_native()?;
    let names: Vec<(&str, &str)> = adapters
        .iter()
        .map(|adapter| (adapter.id.as_str(), adapter.name.as_str()))
        .collect();

    let mut errors = Vec::new();
    for adapter in scanned {
        let Some((_, restore_name)) = names.iter().find(|(id, _)| *id == adapter.id) else {
            continue;
        };
        if !adapter.has_residual_loopback {
            continue;
        }
        let name = if !restore_name.is_empty() {
            *restore_name
        } else {
            adapter.name.as_str()
        };
        if name.is_empty() {
            errors.push(PlatformError::message(format!(
                "网卡 [{}] 仍残留回环 DNS，但缺少网卡名无法兜底重置",
                adapter.id
            )));
            continue;
        }
        if let Err(error) = reset_adapter_dns_netsh(executor, name).await {
            errors.push(PlatformError::message(format!(
                "网卡 [{name}] 兜底拉回 DHCP 失败: {error}"
            )));
            continue;
        }
        eprintln!(
            "[DNS] 网卡 [{name}] 还原失败后仍指向本机回环，已通过 netsh 兜底重置为 DHCP（原始快照保留，可再次恢复）"
        );
    }
    join_errors(errors)
}

fn join_errors(errors: Vec<PlatformError>) -> PlatformResult<()> {
    if errors.is_empty() {
        Ok(())
    } else {
        Err(PlatformError::message(
            errors
                .iter()
                .map(ToString::to_string)
                .collect::<Vec<_>>()
                .join("\n"),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_cases_match_windows_acceptance() {
        let cases = [
            ("192.168.1.1", false, "192.168.1.1", true),
            (" 192.168.1.1 ", false, "192.168.1.1", true),
            ("192.168.1.1:53", false, "192.168.1.1", true),
            ("[fe80::1]", true, "fe80::1", true),
            ("[fe80::1]:53", true, "fe80::1", true),
            ("fe80::1%12", true, "fe80::1", true),
            ("2606:4700:4700::1111", true, "2606:4700:4700::1111", true),
            (
                "2408:844B:2030:FC4D::F9",
                true,
                "2408:844b:2030:fc4d::f9",
                true,
            ),
            ("fe80::1", false, "", false),
            ("192.168.1.1", true, "", false),
            ("::ffff:192.168.1.1", true, "", false),
            ("https://doh.pub/dns-query", false, "", false),
            ("dns.google", false, "", false),
            ("", false, "", false),
            ("   ", true, "", false),
        ];
        for (raw, is_ipv6, expected, ok) in cases {
            let (value, accepted) = normalize_dns_address(raw, is_ipv6);
            assert_eq!(accepted, ok, "acceptance for {raw:?}/{is_ipv6}");
            assert_eq!(value, expected, "value for {raw:?}/{is_ipv6}");
        }
    }

    #[test]
    fn servers_are_partitioned_and_deduplicated() {
        let input = vec![
            "8.8.8.8".to_string(),
            "fe80::1%12".to_string(),
            "1.1.1.1:53".to_string(),
            "https://doh.pub/dns-query".to_string(),
            " 8.8.8.8 ".to_string(),
        ];
        let (kept, dropped) = normalize_servers_for_stack(&input, false);
        assert_eq!(kept, vec!["8.8.8.8".to_string(), "1.1.1.1".to_string()]);
        assert_eq!(
            dropped,
            vec![
                "fe80::1%12".to_string(),
                "https://doh.pub/dns-query".to_string()
            ]
        );
    }

    #[test]
    fn ipv6_stack_keeps_loopback_but_strips_brackets() {
        let input = vec![
            "192.168.1.1".to_string(),
            "2606:4700:4700::1111".to_string(),
            "[::1]".to_string(),
        ];
        let (kept, dropped) = normalize_servers_for_stack(&input, true);
        assert_eq!(
            kept,
            vec!["2606:4700:4700::1111".to_string(), "::1".to_string()]
        );
        assert_eq!(dropped, vec!["192.168.1.1".to_string()]);
    }

    #[test]
    fn invalid_guid_is_rejected_before_calling_windows() {
        assert!(parse_guid("invalid-guid").is_none());
        assert!(parse_guid("{00000000-0000-0000-0000-000000000000}").is_some());
    }
}
