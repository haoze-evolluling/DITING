//! Network predicates shared by both OS backends.
//!
//! The virtual-adapter regex is copied verbatim from the Go service because it drives which
//! adapters may be taken over: a false positive means a user's VPN stops resolving, a false
//! negative means the service rewrites DNS on a tunnel it cannot see.

use std::net::{IpAddr, Ipv4Addr};
use std::sync::OnceLock;

use diting_desktop_api::platform_types::{AdapterState, LANAddressInfo};
use regex::Regex;

const VIRTUAL_PATTERN: &str = "(?i)(Hyper-V|Virtual|VMware|VirtualBox|TAP|TUN|singbox|sing-tun|VPN|Tailscale|WireGuard|ZeroTier|Loopback|Npcap|Clat|WFP|WAN Miniport|Default Switch|Host-Only|vEthernet|WSL|Docker|Bluetooth|蓝牙|Radmin|Hamachi|veth|virbr|br-|docker0|wg[0-9])";

fn virtual_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(VIRTUAL_PATTERN).expect("virtual pattern compiles"))
}

/// `IsVirtualAdapter`: an explicit virtual flag, or a name/description speaking for itself.
pub fn is_virtual_adapter(name: &str, description: &str, virtual_flag: bool) -> bool {
    if virtual_flag {
        return true;
    }
    virtual_regex().is_match(name) || virtual_regex().is_match(description)
}

/// `HasValidIPv4Gateway`: routable IPv4, not empty/zero/loopback.
pub fn has_valid_ipv4_gateway(gateway: &str) -> bool {
    let gateway = gateway.trim();
    if gateway.is_empty() || gateway == "0.0.0.0" {
        return false;
    }
    match gateway.parse::<Ipv4Addr>() {
        Ok(ip) => !ip.is_loopback() && !ip.is_unspecified(),
        Err(_) => false,
    }
}

/// Returns true for loopback, unspecified, `localhost`, and the matching textual prefixes.
pub fn is_loopback_or_local_ip(text: &str) -> bool {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return false;
    }
    // Try the literal first: `host_part` would read `::1` as host `:` plus port `1`.
    if let Ok(ip) = trimmed.parse::<IpAddr>() {
        return ip.is_loopback() || ip.is_unspecified();
    }
    let host = host_part(trimmed).trim_matches(['[', ']']);
    if let Ok(ip) = host.parse::<IpAddr>() {
        return ip.is_loopback() || ip.is_unspecified();
    }
    let lower = host.to_ascii_lowercase();
    lower.starts_with("127.")
        || lower == "::1"
        || lower == "0.0.0.0"
        || lower == "::"
        || lower == "localhost"
}

/// Drops loopback/unspecified entries, trimming whitespace.
pub fn filter_loopback_ips(ips: &[String]) -> Vec<String> {
    ips.iter()
        .filter(|ip| !is_loopback_or_local_ip(ip))
        .map(|ip| ip.trim().to_string())
        .filter(|ip| !ip.is_empty())
        .collect()
}

/// `CleanAdapterState`: removes our own takeover address from the snapshot; an empty list becomes
/// DHCP rather than static, so a restore can never pin the adapter to `127.0.0.1`.
pub fn clean_adapter_state(adapter: &AdapterState) -> AdapterState {
    let mut cleaned = adapter.clone();
    cleaned.ipv4_dns = filter_loopback_ips(&adapter.ipv4_dns);
    cleaned.ipv6_dns = filter_loopback_ips(&adapter.ipv6_dns);
    if cleaned.ipv4_dns.is_empty() {
        cleaned.ipv4_dhcp = true;
    }
    if cleaned.ipv6_dns.is_empty() {
        cleaned.ipv6_dhcp = true;
    }
    cleaned
}

/// `IsPrivateIPv4` (RFC 1918).
pub fn is_private_ipv4(ip: Ipv4Addr) -> bool {
    let octets = ip.octets();
    octets[0] == 10
        || (octets[0] == 172 && (16..=31).contains(&octets[1]))
        || (octets[0] == 192 && octets[1] == 168)
}

/// One interface/IP pair as reported by the OS.
#[derive(Debug, Clone)]
pub struct InterfaceAddress {
    pub interface: String,
    pub address: IpAddr,
}

/// `extractLANAddresses`: active, non-virtual, non-loopback addresses, private IPv4 first.
pub fn extract_lan_addresses(interfaces: &[InterfaceAddress]) -> Vec<String> {
    let mut private4 = Vec::new();
    let mut other4 = Vec::new();
    let mut v6 = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for entry in interfaces {
        if is_virtual_adapter(&entry.interface, "", false) {
            continue;
        }
        let text = entry.address.to_string();
        if !seen.insert(text.clone()) {
            continue;
        }
        match entry.address {
            IpAddr::V4(ip) => {
                if ip.is_loopback()
                    || ip.is_unspecified()
                    || ip.is_multicast()
                    || ip.is_link_local()
                    || ip.is_broadcast()
                {
                    continue;
                }
                if is_private_ipv4(ip) {
                    private4.push(text);
                } else {
                    other4.push(text);
                }
            }
            IpAddr::V6(ip) => {
                if ip.is_loopback()
                    || ip.is_unspecified()
                    || ip.is_multicast()
                    || ip.is_unicast_link_local()
                {
                    continue;
                }
                v6.push(text);
            }
        }
    }
    private4.sort();
    other4.sort();
    v6.sort();
    let mut result = private4;
    result.extend(other4);
    result.extend(v6);
    result
}

/// Same selection as [`extract_lan_addresses`] but keeps the owning interface, for `/dns/lan`.
pub fn extract_lan_address_info(interfaces: &[InterfaceAddress]) -> Vec<LANAddressInfo> {
    let allowed: Vec<String> = extract_lan_addresses(interfaces);
    interfaces
        .iter()
        .filter(|entry| {
            !is_virtual_adapter(&entry.interface, "", false)
                && allowed.contains(&entry.address.to_string())
        })
        .map(|entry| LANAddressInfo {
            ip: entry.address.to_string(),
            interface_name: entry.interface.clone(),
            is_ipv6: entry.address.is_ipv6(),
        })
        .collect()
}

fn host_part(text: &str) -> &str {
    if let Some(rest) = text.strip_prefix('[') {
        if let Some((host, _)) = rest.split_once(']') {
            return host;
        }
    }
    match text.rsplit_once(':') {
        Some((host, port)) if port.chars().all(|ch| ch.is_ascii_digit()) => host,
        _ => text.trim_matches(['[', ']']),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn virtual_names_are_recognized() {
        assert!(is_virtual_adapter("vEthernet (WSL)", "", false));
        assert!(is_virtual_adapter("eth0", "Tailscale Tunnel", false));
        assert!(!is_virtual_adapter("以太网", "Intel(R) Ethernet", false));
        assert!(is_virtual_adapter("eth0", "", true));
    }

    #[test]
    fn loopback_filter_handles_ports_and_unspecified() {
        let ips = vec![
            "127.0.0.1".to_string(),
            "[::1]:53".to_string(),
            "8.8.8.8".to_string(),
            "0.0.0.0".to_string(),
        ];
        assert_eq!(filter_loopback_ips(&ips), vec!["8.8.8.8".to_string()]);
    }

    #[test]
    fn cleaned_state_becomes_dhcp_when_empty() {
        let adapter = AdapterState {
            ipv4_dns: vec!["127.0.0.1".into()],
            ipv4_dhcp: false,
            ipv6_dhcp: false,
            ..AdapterState::default()
        };
        let cleaned = clean_adapter_state(&adapter);
        assert!(cleaned.ipv4_dhcp);
        assert!(cleaned.ipv6_dhcp);
        assert!(cleaned.ipv4_dns.is_empty());
    }

    #[test]
    fn lan_addresses_prefer_private_ipv4() {
        let entries = vec![
            InterfaceAddress {
                interface: "eth0".into(),
                address: "8.8.8.8".parse().unwrap(),
            },
            InterfaceAddress {
                interface: "eth0".into(),
                address: "192.168.1.20".parse().unwrap(),
            },
            InterfaceAddress {
                interface: "wg0".into(),
                address: "10.9.9.9".parse().unwrap(),
            },
        ];
        assert_eq!(
            extract_lan_addresses(&entries),
            vec!["192.168.1.20".to_string(), "8.8.8.8".to_string()]
        );
    }
}
