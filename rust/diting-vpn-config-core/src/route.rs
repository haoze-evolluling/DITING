//! TUN parameters and route plans for the two tunnel services.
//!
//! The Android side still owns `VpnService.Builder`, the interface label and the
//! ConnectivityManager probe; this module owns every address, DNS server, route, MTU, blocking
//! flag, IPv6 decision and the excluded-package union, so normal and express mode cannot drift.

use serde_json::{json, Value};

/// Both modes use the same TUN subnet and MTU; the Go engine's `defaultTunMTU` must match.
pub const VPN_ADDRESS_V4: &str = "10.0.0.2";
pub const DNS_SERVER_V4: &str = "10.0.0.1";
pub const VPN_ADDRESS_V6: &str = "fd00:abcd::2";
pub const DNS_SERVER_V6: &str = "fd00:abcd::1";
pub const VPN_MTU: u16 = 1400;

/// Private, loopback, link-local and CGNAT ranges kept outside the full tunnel.
pub const IPV4_BYPASS_LAN_ROUTES: &[(&str, u8)] = &[
    ("1.0.0.0", 8),
    ("2.0.0.0", 7),
    ("4.0.0.0", 6),
    ("8.0.0.0", 7),
    ("11.0.0.0", 8),
    ("12.0.0.0", 6),
    ("16.0.0.0", 4),
    ("32.0.0.0", 3),
    ("64.0.0.0", 3),
    ("96.0.0.0", 4),
    ("112.0.0.0", 7),
    ("114.0.0.0", 8),
    ("115.0.0.0", 8),
    ("116.0.0.0", 6),
    ("120.0.0.0", 7),
    ("122.0.0.0", 7),
    ("124.0.0.0", 7),
    ("126.0.0.0", 8),
    ("128.0.0.0", 3),
    ("160.0.0.0", 5),
    ("168.0.0.0", 8),
    ("169.0.0.0", 9),
    ("169.128.0.0", 10),
    ("169.192.0.0", 11),
    ("169.224.0.0", 12),
    ("169.240.0.0", 13),
    ("169.248.0.0", 14),
    ("169.252.0.0", 15),
    ("169.255.0.0", 16),
    ("170.0.0.0", 7),
    ("172.0.0.0", 12),
    ("172.32.0.0", 11),
    ("172.64.0.0", 10),
    ("172.128.0.0", 9),
    ("173.0.0.0", 8),
    ("174.0.0.0", 7),
    ("176.0.0.0", 4),
    ("192.0.0.0", 9),
    ("192.128.0.0", 11),
    ("192.160.0.0", 13),
    ("192.169.0.0", 16),
    ("192.170.0.0", 15),
    ("192.172.0.0", 14),
    ("192.176.0.0", 12),
    ("192.192.0.0", 10),
    ("193.0.0.0", 8),
    ("194.0.0.0", 7),
    ("196.0.0.0", 6),
    ("200.0.0.0", 5),
    ("208.0.0.0", 4),
];

/// Public resolvers express mode hijacks into the DNS-only TUN.
pub const IPV4_HIJACK_IPS: &[&str] = &[
    "8.8.8.8",
    "8.8.4.4",
    "1.1.1.1",
    "1.0.0.1",
    "9.9.9.9",
    "149.112.112.112",
    "208.67.222.222",
    "208.67.220.220",
    "223.5.5.5",
    "223.6.6.6",
    "119.29.29.29",
    "114.114.114.114",
    "114.114.115.115",
    "180.76.76.76",
    "77.88.8.8",
    "77.88.8.1",
    "94.140.14.14",
    "94.140.14.15",
    "185.228.168.9",
    "185.228.169.9",
    "64.6.64.6",
    "64.6.65.6",
];

pub const IPV6_HIJACK_IPS: &[&str] = &[
    "2001:4860:4860::8888",
    "2001:4860:4860::8844",
    "2606:4700:4700::1111",
    "2606:4700:4700::1001",
    "2620:fe::fe",
    "2620:fe::9",
    "2400:3200::1",
    "2400:3200:baba::1",
];

/// Explicit modes win; anything else follows the physical-link probe.
///
/// The Flutter UI stores the three legacy values `auto` / `disable` / `prefer`, while the old
/// Kotlin agent and exported 1.4.3 backups use `enabled` / `disabled`. Both spellings have to be
/// understood here, otherwise `disable` silently falls through to the probe and re-enables IPv6 on
/// a link that has a (possibly unusable) global address — the regression that made WiFi slow.
pub fn ipv6_enabled(ipv6_mode: &str, physical_support: bool) -> bool {
    match ipv6_mode.trim().to_lowercase().as_str() {
        "enabled" | "prefer" => true,
        "disabled" | "disable" | "off" => false,
        _ => physical_support,
    }
}

/// Whether the caller has to run the (expensive) ConnectivityManager probe at all.
pub fn ipv6_probe_needed(ipv6_mode: &str) -> bool {
    !matches!(
        ipv6_mode.trim().to_lowercase().as_str(),
        "enabled" | "prefer" | "disabled" | "disable" | "off"
    )
}

fn target(address: &str, prefix: u8) -> Value {
    json!({ "address": address, "prefix": prefix })
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

fn normal_plan(enable_ipv6: bool, bypass_lan: bool) -> (Vec<Value>, Vec<&'static str>, Vec<Value>) {
    let mut addresses = vec![target(VPN_ADDRESS_V4, 30)];
    let mut dns_servers = vec![DNS_SERVER_V4];
    if enable_ipv6 {
        addresses.push(target(VPN_ADDRESS_V6, 64));
        dns_servers.push(DNS_SERVER_V6);
    }

    let mut routes: Vec<Value> = Vec::new();
    if bypass_lan {
        routes.extend(
            IPV4_BYPASS_LAN_ROUTES
                .iter()
                .map(|(address, prefix)| target(address, *prefix)),
        );
        routes.push(target(DNS_SERVER_V4, 32));
        if enable_ipv6 {
            routes.push(target("2000::", 3));
            routes.push(target(DNS_SERVER_V6, 128));
        }
    } else {
        routes.push(target("0.0.0.0", 0));
        if enable_ipv6 {
            routes.push(target("::", 0));
        }
    }
    (addresses, dns_servers, routes)
}

fn express_plan(enable_ipv6: bool) -> (Vec<Value>, Vec<&'static str>, Vec<Value>) {
    let mut addresses = vec![target(VPN_ADDRESS_V4, 30)];
    let mut dns_servers = vec![DNS_SERVER_V4];
    let mut routes = vec![target("10.0.0.0", 30)];
    routes.extend(IPV4_HIJACK_IPS.iter().map(|address| target(address, 32)));
    if enable_ipv6 {
        addresses.push(target(VPN_ADDRESS_V6, 64));
        dns_servers.push(DNS_SERVER_V6);
        routes.push(target(DNS_SERVER_V6, 128));
        routes.extend(IPV6_HIJACK_IPS.iter().map(|address| target(address, 128)));
    }
    (addresses, dns_servers, routes)
}

/// Builds one plan; `None` means the mode is not `normal` or `express`.
pub fn route_plan(
    mode: &str,
    ipv6_mode: &str,
    physical_ipv6: bool,
    bypass_lan: bool,
    excluded: &[String],
    self_package: &str,
    proxy_package: &str,
) -> Option<Value> {
    let enable_ipv6 = ipv6_enabled(ipv6_mode, physical_ipv6);
    let (addresses, dns_servers, routes) = match mode {
        "normal" => normal_plan(enable_ipv6, bypass_lan),
        "express" => express_plan(enable_ipv6),
        _ => return None,
    };
    Some(json!({
        "enableIpv6": enable_ipv6,
        "mtu": VPN_MTU,
        "blocking": true,
        "addresses": addresses,
        "dnsServers": dns_servers,
        "routes": routes,
        "excludedPackages": excluded_packages(excluded, self_package, proxy_package),
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn routes(plan: &Value) -> Vec<(String, u64)> {
        plan["routes"]
            .as_array()
            .unwrap()
            .iter()
            .map(|route| {
                (
                    route["address"].as_str().unwrap().to_owned(),
                    route["prefix"].as_u64().unwrap(),
                )
            })
            .collect()
    }

    #[test]
    fn ipv6_mode_is_explicit_or_follows_the_probe() {
        assert!(ipv6_enabled("enabled", false));
        assert!(!ipv6_enabled("disabled", true));
        assert!(ipv6_enabled("auto", true));
        assert!(!ipv6_enabled("AUTO", false));
        // The Flutter UI's own storage values must not fall through to the probe.
        assert!(!ipv6_enabled("disable", true));
        assert!(ipv6_enabled("prefer", false));
        assert!(ipv6_probe_needed("auto"));
        assert!(!ipv6_probe_needed(" Enabled "));
        assert!(!ipv6_probe_needed("ENABLED"));
        assert!(!ipv6_probe_needed("Disabled"));
        assert!(!ipv6_probe_needed("disable"));
        assert!(!ipv6_probe_needed("prefer"));
    }

    #[test]
    fn normal_full_tunnel_uses_the_default_route() {
        let plan = route_plan("normal", "enabled", false, false, &[], "com.self", "").unwrap();
        assert_eq!(plan["mtu"], 1400);
        assert_eq!(plan["blocking"], true);
        assert_eq!(plan["dnsServers"], json!(["10.0.0.1", "fd00:abcd::1"]));
        assert_eq!(
            routes(&plan),
            vec![("0.0.0.0".to_string(), 0), ("::".to_string(), 0),]
        );
        assert_eq!(plan["excludedPackages"], json!(["com.self"]));
    }

    #[test]
    fn normal_bypass_lan_hides_private_ranges_and_keeps_dns() {
        let plan = route_plan(
            "normal",
            "disabled",
            true,
            true,
            &["com.app".to_string()],
            "com.self",
            "com.proxy",
        )
        .unwrap();
        assert_eq!(plan["enableIpv6"], false);
        assert_eq!(plan["addresses"].as_array().unwrap().len(), 1);
        assert_eq!(plan["dnsServers"], json!(["10.0.0.1"]));
        let routes = routes(&plan);
        assert_eq!(routes.first().unwrap(), &("1.0.0.0".to_string(), 8));
        assert_eq!(routes.last().unwrap(), &("10.0.0.1".to_string(), 32));
        assert_eq!(routes.len(), IPV4_BYPASS_LAN_ROUTES.len() + 1);
        assert_eq!(
            plan["excludedPackages"],
            json!(["com.app", "com.self", "com.proxy"])
        );
    }

    #[test]
    fn normal_bypass_lan_with_ipv6_adds_the_global_and_dns_routes() {
        let plan = route_plan("normal", "enabled", false, true, &[], "com.self", "").unwrap();
        let routes = routes(&plan);
        assert!(routes.contains(&("2000::".to_string(), 3)));
        assert!(routes.contains(&("fd00:abcd::1".to_string(), 128)));
        assert_eq!(plan["addresses"].as_array().unwrap().len(), 2);
        assert_eq!(plan["dnsServers"], json!(["10.0.0.1", "fd00:abcd::1"]));
    }

    #[test]
    fn express_hijacks_public_v4_and_v6_resolvers() {
        let plan = route_plan("express", "auto", true, false, &[], "com.self", "").unwrap();
        assert_eq!(plan["enableIpv6"], true);
        let routes = routes(&plan);
        assert_eq!(routes.first().unwrap(), &("10.0.0.0".to_string(), 30));
        assert_eq!(
            routes.len(),
            1 + IPV4_HIJACK_IPS.len() + 1 + IPV6_HIJACK_IPS.len()
        );
        assert!(routes.contains(&("8.8.8.8".to_string(), 32)));
        assert!(routes.contains(&("fd00:abcd::1".to_string(), 128)));
        assert!(routes.contains(&("2001:4860:4860::8888".to_string(), 128)));
    }

    #[test]
    fn express_without_ipv6_keeps_only_the_v4_hijack_set() {
        let plan = route_plan("express", "disabled", true, false, &[], "com.self", "").unwrap();
        assert_eq!(plan["enableIpv6"], false);
        assert_eq!(plan["addresses"].as_array().unwrap().len(), 1);
        assert_eq!(routes(&plan).len(), 1 + IPV4_HIJACK_IPS.len());
        assert_eq!(plan["dnsServers"], json!(["10.0.0.1"]));
    }

    #[test]
    fn excluded_packages_drop_blanks_and_duplicates() {
        let plan = route_plan(
            "normal",
            "disabled",
            false,
            true,
            &[
                "com.a".to_string(),
                " ".to_string(),
                "com.self".to_string(),
                "com.a".to_string(),
            ],
            "com.self",
            "",
        )
        .unwrap();
        assert_eq!(plan["excludedPackages"], json!(["com.a", "com.self"]));
    }

    #[test]
    fn unknown_mode_is_rejected() {
        assert!(route_plan("server", "auto", true, true, &[], "com.self", "").is_none());
    }
}
