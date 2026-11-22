use serde_json::Value;

use super::*;

fn owned(items: &[&str]) -> Vec<String> {
    items.iter().map(|item| (*item).to_owned()).collect()
}

fn plan(
    tunnel_ipv6: bool,
    include: &[&str],
    exclude: &[&str],
    bypass_private: bool,
    clat: bool,
) -> Value {
    route_plan(
        tunnel_ipv6,
        &owned(include),
        &owned(exclude),
        bypass_private,
        clat,
        &[],
        "com.self",
        "",
    )
}

fn routes(plan: &Value) -> Vec<(String, u64)> {
    plan["routes"]
        .as_array()
        .expect("routes must be an array")
        .iter()
        .map(|route| {
            (
                route["address"].as_str().unwrap().to_owned(),
                route["prefix"].as_u64().unwrap(),
            )
        })
        .collect()
}

fn addresses(plan: &Value) -> Vec<(String, u64)> {
    plan["addresses"]
        .as_array()
        .expect("addresses must be an array")
        .iter()
        .map(|address| {
            (
                address["address"].as_str().unwrap().to_owned(),
                address["prefix"].as_u64().unwrap(),
            )
        })
        .collect()
}

fn has(routes: &[(String, u64)], address: &str, prefix: u64) -> bool {
    routes
        .iter()
        .any(|(item, bits)| item == address && *bits == prefix)
}

#[test]
fn default_full_tunnel_is_ipv4_only() {
    let plan = plan(false, &[], &[], false, false);
    assert_eq!(plan["enableIpv6"], false);
    assert_eq!(plan["mtu"], 1400);
    assert_eq!(plan["blocking"], true);
    assert_eq!(addresses(&plan), vec![(VPN_ADDRESS_V4.to_owned(), 30)]);
    assert_eq!(plan["dnsServers"], serde_json::json!([DNS_SERVER_V4]));
    assert_eq!(routes(&plan), vec![("0.0.0.0".to_owned(), 0)]);
}

#[test]
fn tunnel_ipv6_adds_the_v6_default_route() {
    let plan = plan(true, &[], &[], false, false);
    assert_eq!(plan["enableIpv6"], true);
    assert_eq!(
        addresses(&plan),
        vec![
            (VPN_ADDRESS_V4.to_owned(), 30),
            (VPN_ADDRESS_V6.to_owned(), 64)
        ]
    );
    assert_eq!(
        plan["dnsServers"],
        serde_json::json!([DNS_SERVER_V4, DNS_SERVER_V6])
    );
    assert_eq!(
        routes(&plan),
        vec![("0.0.0.0".to_owned(), 0), ("::".to_owned(), 0)]
    );
}

#[test]
fn bypass_private_excludes_private_ranges_and_keeps_dns() {
    let plan = plan(false, &[], &[], true, false);
    let routes = routes(&plan);
    assert!(has(&routes, "1.0.0.0", 8));
    assert!(has(&routes, DNS_SERVER_V4, 32));
    assert!(!routes
        .iter()
        .any(|(address, prefix)| address.starts_with("10.") && *prefix < 32));
    assert!(!has(&routes, "0.0.0.0", 0));
    assert!(!routes
        .iter()
        .any(|(address, _)| address.starts_with("192.168.")));
}

#[test]
fn include_and_exclude_produce_minimal_routes() {
    let plan = plan(false, &["10.0.0.0/8"], &["10.128.0.0/9"], false, false);
    assert_eq!(routes(&plan), vec![("10.0.0.0".to_owned(), 9)]);
}

#[test]
fn tunnel_ipv6_off_drops_v6_includes() {
    let plan = plan(false, &["2001:db8::/32"], &[], false, false);
    let routes = routes(&plan);
    assert_eq!(routes, vec![("0.0.0.0".to_owned(), 0)]);
    assert_eq!(addresses(&plan), vec![(VPN_ADDRESS_V4.to_owned(), 30)]);
}

#[test]
fn clat_keeps_only_ipv6() {
    let plan = plan(false, &[], &[], false, true);
    assert_eq!(plan["enableIpv6"], true);
    assert_eq!(addresses(&plan), vec![(VPN_ADDRESS_V6.to_owned(), 64)]);
    assert_eq!(plan["dnsServers"], serde_json::json!([DNS_SERVER_V6]));
    assert_eq!(routes(&plan), vec![("::".to_owned(), 0)]);
}

#[test]
fn clat_with_bypass_private_forces_the_dns_host() {
    let plan = plan(false, &[], &[], true, true);
    let routes = routes(&plan);
    assert!(has(&routes, DNS_SERVER_V6, 128));
    assert!(!routes.iter().any(|(address, _)| !address.contains(':')));
    assert!(!has(&routes, "::", 0));
}

#[test]
fn invalid_route_entries_are_ignored() {
    let plan = plan(false, &["nonsense", "10.0.0.0/8"], &[], false, false);
    assert_eq!(routes(&plan), vec![("10.0.0.0".to_owned(), 8)]);
}

#[test]
fn excluded_packages_drop_blanks_and_duplicates() {
    let plan = route_plan(
        false,
        &[],
        &[],
        false,
        false,
        &owned(&["com.a", " ", "com.self", "com.a"]),
        "com.self",
        "com.proxy",
    );
    assert_eq!(
        plan["excludedPackages"],
        serde_json::json!(["com.a", "com.self", "com.proxy"])
    );
}

#[test]
fn clat_wins_over_a_disabled_tunnel_switch() {
    let plan = plan(false, &[], &["::/0"], false, true);
    assert_eq!(plan["enableIpv6"], true);
    assert_eq!(routes(&plan), vec![(DNS_SERVER_V6.to_owned(), 128)]);
}
