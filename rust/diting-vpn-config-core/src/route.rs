use std::net::{Ipv4Addr, Ipv6Addr};

use serde_json::{json, Value};

mod cidr;

pub const VPN_ADDRESS_V4: &str = "10.0.0.2";
pub const DNS_SERVER_V4: &str = "10.0.0.1";
pub const VPN_ADDRESS_V6: &str = "fd00:abcd::2";
pub const DNS_SERVER_V6: &str = "fd00:abcd::1";
pub const VPN_MTU: u16 = 1400;

pub const PRIVATE_ROUTE_ADDRESS: &[&str] = &[
    "0.0.0.0/8",
    "10.0.0.0/8",
    "127.0.0.0/8",
    "169.254.0.0/16",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "224.0.0.0/4",
    "255.255.255.255/32",
    "fc00::/7",
    "fe80::/10",
    "ff00::/8",
];

fn target(address: &str, prefix: u8) -> Value {
    json!({ "address": address, "prefix": prefix })
}

fn target_block(block: &cidr::Block) -> Value {
    json!({ "address": cidr::format_address(block), "prefix": block.prefix })
}

fn excluded_packages(excluded: &[String], self_package: &str, proxy_package: &str) -> Vec<String> {
    let mut all: Vec<String> = Vec::new();
    for package in excluded
        .iter()
        .map(String::as_str)
        .chain([self_package, proxy_package])
    {
        if package.trim().is_empty() || all.iter().any(|item| item == package) {
            continue;
        }
        all.push(package.to_owned());
    }
    all
}

fn force_dns_hosts(blocks: &mut Vec<cidr::Block>, enable_ipv6: bool, clat: bool) {
    if !clat {
        if let Ok(address) = DNS_SERVER_V4.parse::<Ipv4Addr>() {
            cidr::force_host(blocks, 32, u32::from(address) as u128);
        }
    }
    if enable_ipv6 {
        if let Ok(address) = DNS_SERVER_V6.parse::<Ipv6Addr>() {
            cidr::force_host(blocks, 128, u128::from(address));
        }
    }
}

#[allow(clippy::too_many_arguments)]
pub fn route_plan(
    tunnel_ipv6: bool,
    route_address: &[String],
    route_exclude_address: &[String],
    bypass_private: bool,
    clat: bool,
    excluded: &[String],
    self_package: &str,
    proxy_package: &str,
) -> Value {
    let enable_ipv6 = clat || tunnel_ipv6;

    let mut excludes = route_exclude_address.to_vec();
    if bypass_private {
        excludes.extend(PRIVATE_ROUTE_ADDRESS.iter().map(|item| (*item).to_owned()));
    }
    let mut blocks = cidr::subtract_cidrs(route_address, &excludes, true);
    blocks.retain(|block| match block.bits {
        32 => !clat,
        128 => enable_ipv6,
        _ => false,
    });
    force_dns_hosts(&mut blocks, enable_ipv6, clat);
    blocks.sort_by_key(|block| (block.bits, block.start));

    let mut addresses = Vec::new();
    if !clat {
        addresses.push(target(VPN_ADDRESS_V4, 30));
    }
    if enable_ipv6 {
        addresses.push(target(VPN_ADDRESS_V6, 64));
    }

    let mut dns_servers = Vec::new();
    if !clat {
        dns_servers.push(DNS_SERVER_V4);
    }
    if enable_ipv6 {
        dns_servers.push(DNS_SERVER_V6);
    }

    json!({
        "enableIpv6": enable_ipv6,
        "mtu": VPN_MTU,
        "blocking": true,
        "addresses": addresses,
        "dnsServers": dns_servers,
        "routes": blocks.iter().map(target_block).collect::<Vec<_>>(),
        "excludedPackages": excluded_packages(excluded, self_package, proxy_package),
    })
}

#[cfg(test)]
mod tests;
