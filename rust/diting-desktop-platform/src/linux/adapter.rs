//! Linux adapter enumeration: interfaces from `getifaddrs`, gateways from `/proc/net/route`,
//! descriptions from sysfs and per-interface DNS servers from the active backend.

use std::collections::HashMap;
use std::ffi::CStr;
use std::net::{IpAddr, Ipv4Addr};
use std::path::Path;
use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_api::platform_types::AdapterInfo;

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::netutil::{has_valid_ipv4_gateway, is_loopback_or_local_ip, is_virtual_adapter};
use crate::traits::AdapterScanner;

use super::dnsstate;

/// One Linux network interface as reported by `getifaddrs`.
#[derive(Debug, Clone)]
pub(crate) struct NetInterface {
    pub name: String,
    pub index: i32,
    pub flags: u32,
    pub addresses: Vec<IpAddr>,
}

impl NetInterface {
    pub(crate) fn is_loopback(&self) -> bool {
        self.flags & (libc::IFF_LOOPBACK as u32) != 0
    }

    pub(crate) fn is_up(&self) -> bool {
        self.flags & (libc::IFF_UP as u32) != 0
    }

    pub(crate) fn has_point_to_point(&self) -> bool {
        self.flags & (libc::IFF_POINTOPOINT as u32) != 0
    }
}

/// All interfaces, sorted by interface index like Go's `net.Interfaces`.
pub(crate) fn list_managed_interfaces() -> PlatformResult<Vec<NetInterface>> {
    // SAFETY: `getifaddrs` fills a linked list owned by libc; we only read it before the matching
    // `freeifaddrs`, and every pointer is checked for null.
    unsafe {
        let mut head: *mut libc::ifaddrs = std::ptr::null_mut();
        if libc::getifaddrs(&mut head) != 0 {
            return Err(PlatformError::from(std::io::Error::last_os_error()));
        }

        let mut by_name: HashMap<String, NetInterface> = HashMap::new();
        let mut cursor = head;
        while !cursor.is_null() {
            let entry = &*cursor;
            let name = CStr::from_ptr(entry.ifa_name)
                .to_string_lossy()
                .into_owned();
            let index = interface_index(&name);
            let flags = entry.ifa_flags as u32;
            let interface = by_name.entry(name.clone()).or_insert_with(|| NetInterface {
                name,
                index,
                flags,
                addresses: Vec::new(),
            });
            if let Some(address) = sockaddr_to_ip(entry.ifa_addr) {
                interface.addresses.push(address);
            }
            cursor = entry.ifa_next;
        }
        libc::freeifaddrs(head);

        let mut interfaces: Vec<NetInterface> = by_name.into_values().collect();
        interfaces.sort_by(|left, right| {
            left.index
                .cmp(&right.index)
                .then_with(|| left.name.cmp(&right.name))
        });
        Ok(interfaces)
    }
}

fn interface_index(name: &str) -> i32 {
    match std::ffi::CString::new(name) {
        // SAFETY: `if_nametoindex` only reads the NUL-terminated name.
        Ok(value) => unsafe { libc::if_nametoindex(value.as_ptr()) as i32 },
        Err(_) => 0,
    }
}

/// Converts an `AF_INET`/`AF_INET6` `sockaddr` to a Rust address. Other families are ignored.
unsafe fn sockaddr_to_ip(address: *const libc::sockaddr) -> Option<IpAddr> {
    if address.is_null() {
        return None;
    }
    match (*address).sa_family as i32 {
        libc::AF_INET => {
            let socket = &*(address as *const libc::sockaddr_in);
            // `s_addr` holds network-order bytes; `to_ne_bytes` yields them in wire order.
            Some(IpAddr::V4(Ipv4Addr::from(
                socket.sin_addr.s_addr.to_ne_bytes(),
            )))
        }
        libc::AF_INET6 => {
            let socket = &*(address as *const libc::sockaddr_in6);
            Some(IpAddr::V6(std::net::Ipv6Addr::from(
                socket.sin6_addr.s6_addr,
            )))
        }
        _ => None,
    }
}

/// Default IPv4 gateway for `iface`, parsed from the little-endian hex in `/proc/net/route`.
pub(crate) fn read_default_gateway(iface_name: &str) -> String {
    let content = match std::fs::read_to_string("/proc/net/route") {
        Ok(content) => content,
        Err(_) => return String::new(),
    };
    for line in content.lines().skip(1) {
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.len() < 3 {
            continue;
        }
        if fields[0] != iface_name || fields[1] != "00000000" {
            continue;
        }
        let gateway = parse_hex_ipv4(fields[2]);
        if !gateway.is_empty() && gateway != "0.0.0.0" {
            return gateway;
        }
    }
    String::new()
}

/// Converts `/proc`'s little-endian hex IPv4 into dotted decimal.
pub(crate) fn parse_hex_ipv4(value: &str) -> String {
    match u32::from_str_radix(value, 16) {
        Ok(value) => format!(
            "{}.{}.{}.{}",
            value & 0xff,
            (value >> 8) & 0xff,
            (value >> 16) & 0xff,
            (value >> 24) & 0xff
        ),
        Err(_) => String::new(),
    }
}

/// Friendly description from sysfs (`DRIVER=` in the uevent), falling back to the name.
pub(crate) fn iface_description(name: &str) -> String {
    let uevent = Path::new("/sys/class/net").join(name).join("device/uevent");
    if let Ok(content) = std::fs::read_to_string(&uevent) {
        for line in content.split('\n') {
            if let Some(driver) = line.strip_prefix("DRIVER=") {
                let driver = driver.trim();
                if !driver.is_empty() {
                    return driver.to_string();
                }
            }
        }
    }
    name.to_string()
}

/// Native Linux adapter scanner.
pub struct LinuxAdapterScanner {
    executor: Arc<dyn CommandExecutor>,
}

impl LinuxAdapterScanner {
    pub fn new(executor: Arc<dyn CommandExecutor>) -> Self {
        Self { executor }
    }
}

#[async_trait]
impl AdapterScanner for LinuxAdapterScanner {
    async fn scan_all(&self) -> PlatformResult<Vec<AdapterInfo>> {
        let interfaces = list_managed_interfaces()?;
        let servers = dnsstate::scan_configured_dns_servers(self.executor.as_ref()).await;

        let mut results = Vec::with_capacity(interfaces.len());
        for interface in interfaces {
            if interface.is_loopback() {
                continue;
            }

            let description = iface_description(&interface.name);
            let is_virtual = is_virtual_adapter(
                &interface.name,
                &description,
                interface.has_point_to_point(),
            );
            let gateway = read_default_gateway(&interface.name);

            let configured = servers.get(&interface.name);
            let (ipv4_dns, ipv6_dns) = match configured {
                Some(list) => split_servers(list),
                None => (Vec::new(), Vec::new()),
            };
            let status = if interface.is_up() {
                "Up"
            } else {
                "Disconnected"
            };

            results.push(AdapterInfo {
                id: interface.name.clone(),
                name: interface.name,
                description,
                index: interface.index,
                status: status.to_string(),
                gateway,
                ipv4_dhcp: ipv4_dns.is_empty(),
                ipv6_dhcp: ipv6_dns.is_empty(),
                ipv4_dns,
                ipv6_dns,
                is_physical: !is_virtual,
                has_residual_loopback: configured
                    .map(|list| has_loopback_server(list))
                    .unwrap_or(false),
            });
        }
        Ok(results)
    }

    async fn active_physical_adapters(&self) -> PlatformResult<Vec<AdapterInfo>> {
        let all = self.scan_all().await?;
        Ok(all
            .into_iter()
            .filter(|adapter| {
                adapter.is_physical
                    && adapter.status.eq_ignore_ascii_case("Up")
                    && has_valid_ipv4_gateway(&adapter.gateway)
            })
            .collect())
    }
}

/// Splits a server list by address family.
pub(crate) fn split_servers(servers: &[String]) -> (Vec<String>, Vec<String>) {
    let mut ipv4 = Vec::new();
    let mut ipv6 = Vec::new();
    for server in servers {
        let server = server.trim();
        if server.is_empty() {
            continue;
        }
        if server.contains(':') {
            ipv6.push(server.to_string());
        } else {
            ipv4.push(server.to_string());
        }
    }
    (ipv4, ipv6)
}

/// True when any server points at loopback/local.
pub(crate) fn has_loopback_server(servers: &[String]) -> bool {
    servers.iter().any(|server| is_loopback_or_local_ip(server))
}

/// Lists interface names for which `/etc/resolv.conf` should be attributed.
pub(crate) fn iface_usable_for_resolv_conf(interface: &NetInterface) -> bool {
    !interface.is_loopback()
        && interface.is_up()
        && !is_virtual_adapter(&interface.name, "", interface.has_point_to_point())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hex_ipv4_is_little_endian() {
        assert_eq!(parse_hex_ipv4("0100007F"), "127.0.0.1");
        assert_eq!(parse_hex_ipv4("010148C0"), "192.168.1.1");
        assert_eq!(parse_hex_ipv4("not-hex"), "");
    }

    #[test]
    fn servers_split_by_family() {
        let (v4, v6) = split_servers(&[
            " 1.1.1.1 ".into(),
            "2001:db8::1".into(),
            "".into(),
            "8.8.8.8".into(),
        ]);
        assert_eq!(v4, vec!["1.1.1.1".to_string(), "8.8.8.8".to_string()]);
        assert_eq!(v6, vec!["2001:db8::1".to_string()]);
    }

    #[test]
    fn loopback_servers_are_detected() {
        assert!(has_loopback_server(&["127.0.0.1".into()]));
        assert!(!has_loopback_server(&["1.1.1.1".into()]));
    }
}
