use diting_desktop_api::config::AccessControlConfig;

use super::*;

fn config(allowed: &[&str], blocked: &[&str]) -> AccessControlConfig {
    AccessControlConfig {
        allowed_clients: allowed.iter().map(|value| value.to_string()).collect(),
        blocked_clients: blocked.iter().map(|value| value.to_string()).collect(),
    }
}

fn ip(text: &str) -> std::net::IpAddr {
    text.parse().expect("valid test address")
}

#[test]
fn empty_config_allows_everyone() {
    let control = AccessControl::new(&config(&[], &[]));
    assert_eq!(control.check(Some(ip("10.0.0.1"))), (true, String::new()));
    assert_eq!(control.check(None), (true, String::new()));
    assert!(!control.stats().has_allowed);
}

#[test]
fn blocked_list_wins_over_allowed() {
    let control = AccessControl::new(&config(&["10.0.0.0/8"], &["10.0.0.1"]));
    let (allowed, reason) = control.check(Some(ip("10.0.0.1")));
    assert!(!allowed);
    assert!(reason.contains("10.0.0.1"));
    assert!(reason.contains("黑名单"));

    assert_eq!(control.check(Some(ip("10.0.0.2"))), (true, String::new()));
}

#[test]
fn blocked_network_reason_names_the_cidr() {
    let control = AccessControl::new(&config(&[], &["10.0.0.0/8"]));
    let (allowed, reason) = control.check(Some(ip("10.1.2.3")));
    assert!(!allowed);
    assert!(reason.contains("10.0.0.0/8"), "reason was {reason}");
}

#[test]
fn allowlist_rejects_unlisted_clients() {
    let control = AccessControl::new(&config(&["192.168.1.0/24", "10.0.0.5"], &[]));

    assert_eq!(
        control.check(Some(ip("192.168.1.7"))),
        (true, String::new())
    );
    assert_eq!(control.check(Some(ip("10.0.0.5"))), (true, String::new()));

    let (allowed, reason) = control.check(Some(ip("10.0.0.6")));
    assert!(!allowed);
    assert!(reason.contains("allowedClients"), "reason was {reason}");
}

#[test]
fn invalid_entries_are_reported_and_valid_ones_kept() {
    let control = AccessControl::new(&config(
        &["10.0.0.0/33", "not-an-ip", "10.0.0.0/8"],
        &["192.168.0.0/16"],
    ));

    let stats = control.stats();
    assert_eq!(stats.allowed_entries, 1);
    assert_eq!(stats.blocked_entries, 1);
    assert!(stats.has_allowed);

    assert_eq!(control.check(Some(ip("10.1.2.3"))), (true, String::new()));
    assert!(!control.check(Some(ip("192.168.1.1"))).0);
}

#[test]
fn configure_reports_diagnostics() {
    let control = AccessControl::new(&config(&[], &[]));
    let problems = control.configure(&config(&["2001:db8::/32", "bogus"], &[]));
    assert_eq!(problems.len(), 1);
    assert_eq!(control.stats().allowed_entries, 1);
    assert_eq!(
        control.check(Some(ip("2001:db8::1"))),
        (true, String::new())
    );
}

#[test]
fn config_round_trips() {
    let source = config(&["10.0.0.0/8"], &["10.0.0.1"]);
    let control = AccessControl::new(&source);
    assert_eq!(control.config(), source);
}

#[test]
fn v4_mapped_clients_match_ipv4_rules() {
    let control = AccessControl::new(&config(&[], &["10.0.0.0/8"]));
    assert!(!control.check(Some(ip("::ffff:10.1.2.3"))).0);
}
