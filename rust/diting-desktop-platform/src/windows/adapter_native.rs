use std::ffi::{c_void, CStr};
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::ptr;

use diting_desktop_api::platform_types::{AdapterInfo, AdapterState};
use windows_sys::Win32::Foundation::{ERROR_BUFFER_OVERFLOW, ERROR_SUCCESS};
use windows_sys::Win32::NetworkManagement::IpHelper::{
    GAA_FLAG_INCLUDE_GATEWAYS, GAA_FLAG_SKIP_ANYCAST, GAA_FLAG_SKIP_MULTICAST,
};
use windows_sys::Win32::Networking::WinSock::{SOCKADDR_IN, SOCKADDR_IN6, SOCKET_ADDRESS};

use crate::error::{PlatformError, PlatformResult};
use crate::netutil::{
    clean_adapter_state, has_valid_ipv4_gateway, is_virtual_adapter, InterfaceAddress,
};

use super::adapter_registry::{
    check_registry_contains_loopback, get_dhcp_config_from_registry, is_loopback_literal,
    normalize_guid,
};

const IF_OPER_STATUS_UP: i32 = 1;
const IF_TYPE_SOFTWARE_LOOPBACK: u32 = 24;
const IF_TYPE_TUNNEL: u32 = 131;

#[repr(C)]
union AdapterAddressesHead {
    alignment: u64,
    anonymous: AdapterAddressesHeadAnonymous,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct AdapterAddressesHeadAnonymous {
    length: u32,
    if_index: u32,
}

#[repr(C)]
struct IpAdapterAddressEntry {
    anonymous: AdapterAddressesHead,
    next: *mut IpAdapterAddressEntry,
    address: SOCKET_ADDRESS,
}

#[repr(C)]
struct IpAdapterUnicastAddress {
    anonymous: u64,
    next: *mut IpAdapterUnicastAddress,
    address: SOCKET_ADDRESS,
}

#[repr(C)]
struct IpAdapterAddresses {
    anonymous: AdapterAddressesHead,
    next: *mut IpAdapterAddresses,
    adapter_name: *mut u8,
    first_unicast_address: *mut IpAdapterUnicastAddress,
    first_anycast_address: *mut c_void,
    first_multicast_address: *mut c_void,
    first_dns_server_address: *mut IpAdapterAddressEntry,
    dns_suffix: *mut u16,
    description: *mut u16,
    friendly_name: *mut u16,
    physical_address: [u8; 8],
    physical_address_length: u32,
    flags: u32,
    mtu: u32,
    if_type: u32,
    oper_status: i32,
    ipv6_if_index: u32,
    zone_indices: [u32; 16],
    first_prefix: *mut c_void,
    transmit_link_speed: u64,
    receive_link_speed: u64,
    first_wins_server_address: *mut c_void,
    first_gateway_address: *mut IpAdapterAddressEntry,
    ipv4_metric: u32,
    ipv6_metric: u32,
    luid: u64,
    dhcpv4_server: SOCKET_ADDRESS,
    compartment_id: u32,
    network_guid: windows_sys::core::GUID,
    connection_type: u32,
    tunnel_type: u32,
    dhcpv6_server: SOCKET_ADDRESS,
    dhcpv6_client_duid: [u8; 130],
    dhcpv6_client_duid_length: u32,
    dhcpv6_iaid: u32,
    first_dns_suffix: *mut c_void,
}

#[link(name = "iphlpapi")]
extern "system" {
    fn GetAdaptersAddresses(
        family: u32,
        flags: u32,
        reserved: *const c_void,
        adapter_addresses: *mut IpAdapterAddresses,
        size_pointer: *mut u32,
    ) -> u32;
}

pub(crate) fn scan_adapters_native() -> PlatformResult<Vec<AdapterInfo>> {
    let buffer = collect_adapter_buffer()?;
    let mut current = buffer.as_ptr() as *const IpAdapterAddresses;
    let mut results = Vec::new();

    while !current.is_null() {
        let adapter = unsafe { &*current };
        let id = normalize_guid(&unsafe { ansi_ptr_to_string(adapter.adapter_name) });
        let name = unsafe { utf16_ptr_to_string(adapter.friendly_name) };
        let description = unsafe { utf16_ptr_to_string(adapter.description) };
        let index = unsafe { adapter.anonymous.anonymous.if_index } as i32;
        let status = if adapter.oper_status == IF_OPER_STATUS_UP {
            "Up"
        } else {
            "Disconnected"
        }
        .to_string();

        let gateway =
            unsafe { first_ipv4_gateway(adapter.first_gateway_address) }.unwrap_or_default();
        let (v4_dns, v6_dns, dns_residual) =
            unsafe { collect_dns_servers(adapter.first_dns_server_address) };
        let has_residual_loopback = dns_residual || check_registry_contains_loopback(&id);
        let (v4_dhcp, v6_dhcp) = get_dhcp_config_from_registry(&id);

        let virtual_flag = matches!(adapter.if_type, IF_TYPE_SOFTWARE_LOOPBACK | IF_TYPE_TUNNEL);
        let is_physical = !is_virtual_adapter(&name, &description, virtual_flag);

        results.push(AdapterInfo {
            id,
            name,
            description,
            index,
            status,
            gateway,
            ipv4_dhcp: v4_dhcp,
            ipv6_dhcp: v6_dhcp,
            ipv4_dns: filter_loopback_literals(v4_dns),
            ipv6_dns: filter_loopback_literals(v6_dns),
            is_physical,
            has_residual_loopback,
        });

        current = adapter.next;
    }

    Ok(results)
}

pub(crate) fn native_interface_addresses() -> PlatformResult<Vec<InterfaceAddress>> {
    let buffer = collect_adapter_buffer()?;
    let mut current = buffer.as_ptr() as *const IpAdapterAddresses;
    let mut results = Vec::new();

    while !current.is_null() {
        let adapter = unsafe { &*current };
        if adapter.oper_status == IF_OPER_STATUS_UP && adapter.if_type != IF_TYPE_SOFTWARE_LOOPBACK
        {
            let name = unsafe { utf16_ptr_to_string(adapter.friendly_name) };
            let mut unicast = adapter.first_unicast_address;
            while !unicast.is_null() {
                let entry = unsafe { &*unicast };
                if let Some(address) = unsafe { socket_address_ip(&entry.address) } {
                    results.push(InterfaceAddress {
                        interface: name.clone(),
                        address,
                    });
                }
                unicast = entry.next;
            }
        }
        current = adapter.next;
    }

    Ok(results)
}

fn collect_adapter_buffer() -> PlatformResult<Vec<u8>> {
    let flags = GAA_FLAG_INCLUDE_GATEWAYS | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_ANYCAST;
    let mut size: u32 = 16_384;
    let mut buffer = vec![0u8; size as usize];

    for _ in 0..5 {
        let status = unsafe {
            GetAdaptersAddresses(
                0,
                flags,
                ptr::null(),
                buffer.as_mut_ptr() as *mut IpAdapterAddresses,
                &mut size,
            )
        };
        if status == ERROR_SUCCESS {
            return Ok(buffer);
        }
        if status != ERROR_BUFFER_OVERFLOW {
            return Err(PlatformError::message(format!(
                "枚举网卡失败: Windows 错误码 {status}"
            )));
        }
        buffer = vec![0u8; size as usize];
    }

    Err(PlatformError::message("枚举网卡失败: 缓冲区大小反复不足"))
}

unsafe fn socket_address_ip(address: &SOCKET_ADDRESS) -> Option<IpAddr> {
    if address.lpSockaddr.is_null() || address.iSockaddrLength < 2 {
        return None;
    }
    let family = *(address.lpSockaddr as *const u16);
    match family {
        2 => {
            let sockaddr = &*(address.lpSockaddr as *const SOCKADDR_IN);
            let raw = sockaddr.sin_addr.S_un.S_addr;
            Some(IpAddr::V4(Ipv4Addr::from(u32::from_be(raw))))
        }
        23 => {
            let sockaddr = &*(address.lpSockaddr as *const SOCKADDR_IN6);
            Some(IpAddr::V6(Ipv6Addr::from(sockaddr.sin6_addr.u.Byte)))
        }
        _ => None,
    }
}

unsafe fn first_ipv4_gateway(mut entry: *mut IpAdapterAddressEntry) -> Option<String> {
    while !entry.is_null() {
        let item = &*entry;
        if let Some(IpAddr::V4(address)) = socket_address_ip(&item.address) {
            let text = address.to_string();
            if has_valid_ipv4_gateway(&text) {
                return Some(text);
            }
        }
        entry = item.next;
    }
    None
}

unsafe fn collect_dns_servers(
    mut entry: *mut IpAdapterAddressEntry,
) -> (Vec<String>, Vec<String>, bool) {
    let mut v4 = Vec::new();
    let mut v6 = Vec::new();
    let mut saw_loopback = false;

    while !entry.is_null() {
        let item = &*entry;
        if let Some(address) = socket_address_ip(&item.address) {
            match address {
                IpAddr::V4(address) => {
                    let text = address.to_string();
                    if is_loopback_literal(&text) {
                        saw_loopback = true;
                    } else {
                        v4.push(text);
                    }
                }
                IpAddr::V6(address) => {
                    let text = address.to_string();
                    if is_loopback_literal(&text) {
                        saw_loopback = true;
                    } else if !text.to_ascii_lowercase().starts_with("fec0:") {
                        v6.push(text);
                    }
                }
            }
        }
        entry = item.next;
    }

    (v4, v6, saw_loopback)
}

unsafe fn ansi_ptr_to_string(pointer: *const u8) -> String {
    if pointer.is_null() {
        return String::new();
    }
    CStr::from_ptr(pointer as *const i8)
        .to_string_lossy()
        .into_owned()
}

unsafe fn utf16_ptr_to_string(pointer: *const u16) -> String {
    if pointer.is_null() {
        return String::new();
    }
    let mut length = 0usize;
    while *pointer.add(length) != 0 {
        length += 1;
    }
    String::from_utf16_lossy(std::slice::from_raw_parts(pointer, length))
}

fn filter_loopback_literals(ips: Vec<String>) -> Vec<String> {
    ips.into_iter()
        .filter(|ip| !is_loopback_literal(ip))
        .map(|ip| ip.trim().to_string())
        .filter(|ip| !ip.is_empty())
        .collect()
}

pub(crate) fn clean_state_for_windows(adapter: &AdapterState) -> AdapterState {
    let mut cleaned = clean_adapter_state(adapter);
    cleaned.ipv4_dns.retain(|ip| !is_loopback_literal(ip));
    cleaned.ipv6_dns.retain(|ip| !is_loopback_literal(ip));
    if cleaned.ipv4_dns.is_empty() {
        cleaned.ipv4_dhcp = true;
    }
    if cleaned.ipv6_dns.is_empty() {
        cleaned.ipv6_dhcp = true;
    }
    cleaned
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bare_loopback_literals_are_filtered() {
        let values = vec![
            "::1".to_string(),
            "8.8.8.8".to_string(),
            "127.0.0.1".to_string(),
            "2606:4700:4700::1111".to_string(),
        ];
        assert_eq!(
            filter_loopback_literals(values),
            vec!["8.8.8.8".to_string(), "2606:4700:4700::1111".to_string()]
        );
    }
}
