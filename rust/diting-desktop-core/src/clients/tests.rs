use diting_desktop_api::config::{ClientAlias, ClientConfig, ClientGroup, DurationValue};

use super::*;

fn group(id: &str, clients: &[&str]) -> ClientGroup {
    ClientGroup {
        id: id.to_string(),
        name: id.to_string(),
        enabled: true,
        clients: clients.iter().map(|value| value.to_string()).collect(),
        ..ClientGroup::default()
    }
}

fn alias(ip: &str, name: &str) -> ClientAlias {
    ClientAlias {
        ip: ip.to_string(),
        name: name.to_string(),
    }
}

#[test]
fn longest_prefix_wins() {
    let groups = vec![
        group("broad", &["10.0.0.0/8"]),
        group("narrow", &["10.1.0.0/16"]),
    ];
    let (resolver, problems) = GroupResolver::new(&groups, true);
    assert!(problems.is_empty());
    assert_eq!(
        resolver.resolve("10.1.2.3".parse().unwrap()),
        "narrow".to_string()
    );
    assert_eq!(
        resolver.resolve("10.2.3.4".parse().unwrap()),
        "broad".to_string()
    );
    assert_eq!(
        resolver.resolve("192.168.1.1".parse().unwrap()),
        DEFAULT_GROUP.to_string()
    );
}

#[test]
fn equal_prefix_keeps_declaration_order() {
    let groups = vec![
        group("first", &["10.0.0.0/24"]),
        group("second", &["10.0.0.0/24"]),
    ];
    let (resolver, problems) = GroupResolver::new(&groups, true);
    assert!(problems.is_empty());
    assert_eq!(
        resolver.resolve("10.0.0.5".parse().unwrap()),
        "first".to_string()
    );
}

#[test]
fn invalid_members_are_reported_and_skipped() {
    let groups = vec![group("bad", &["not-an-ip", "10.0.0.0/33", "10.0.0.1"])];
    let (resolver, problems) = GroupResolver::new(&groups, true);
    assert_eq!(problems.len(), 2);
    assert_eq!(
        resolver.resolve("10.0.0.1".parse().unwrap()),
        "bad".to_string()
    );
}

#[test]
fn disabled_and_reserved_groups_are_ignored() {
    let mut disabled = group("off", &["10.0.0.0/8"]);
    disabled.enabled = false;
    let groups = vec![
        disabled,
        group("default", &["192.168.0.0/16"]),
        group("live", &["172.16.0.0/12"]),
    ];
    let (resolver, problems) = GroupResolver::new(&groups, true);
    assert_eq!(problems.len(), 1);
    assert_eq!(
        resolver.resolve("10.1.2.3".parse().unwrap()),
        DEFAULT_GROUP.to_string()
    );
    assert_eq!(
        resolver.resolve("192.168.1.1".parse().unwrap()),
        DEFAULT_GROUP.to_string()
    );
    assert_eq!(
        resolver.resolve("172.16.1.1".parse().unwrap()),
        "live".to_string()
    );
}

#[test]
fn groups_disabled_always_defaults() {
    let groups = vec![group("lan", &["10.0.0.0/8"])];
    let (resolver, problems) = GroupResolver::new(&groups, false);
    assert!(problems.is_empty());
    assert_eq!(
        resolver.resolve("10.1.2.3".parse().unwrap()),
        DEFAULT_GROUP.to_string()
    );
    assert_eq!(resolver.groups(), groups);
}

#[test]
fn v4_mapped_clients_and_networks_match_ipv4() {
    let groups = vec![group("mapped", &["::ffff:10.0.0.0/120"])];
    let (resolver, problems) = GroupResolver::new(&groups, true);
    assert!(problems.is_empty());
    assert_eq!(
        resolver.resolve("10.0.0.7".parse().unwrap()),
        "mapped".to_string()
    );
    assert_eq!(
        resolver.resolve("::ffff:10.0.0.7".parse().unwrap()),
        "mapped".to_string()
    );
}

#[test]
fn aliases_are_first_wins_and_normalized() {
    let config = ClientConfig {
        aliases: vec![
            alias("10.0.0.1", "Laptop"),
            alias("10.0.0.1", "Duplicate"),
            alias("::ffff:10.0.0.2", "Mapped"),
            alias("", "empty-ip"),
            alias("not-an-ip", "bad"),
        ],
        ..ClientConfig::default()
    };
    let directory = ClientDirectory::new(&config);

    assert_eq!(directory.identify("10.0.0.1".parse().unwrap()), "Laptop");
    assert_eq!(
        directory.alias("10.0.0.1".parse().unwrap()).as_deref(),
        Some("Laptop")
    );
    assert_eq!(directory.identify("10.0.0.2".parse().unwrap()), "Mapped");
    assert_eq!(
        directory
            .alias("::ffff:10.0.0.1".parse().unwrap())
            .as_deref(),
        Some("Laptop")
    );
}

#[test]
fn identification_disabled_returns_only_aliases() {
    let config = ClientConfig {
        enabled: false,
        aliases: vec![alias("10.0.0.1", "Laptop")],
        ..ClientConfig::default()
    };
    let directory = ClientDirectory::new(&config);

    assert_eq!(directory.identify("10.0.0.1".parse().unwrap()), "Laptop");
    assert_eq!(directory.identify("10.0.0.2".parse().unwrap()), "");
}

#[test]
fn activity_is_recorded_and_info_is_sorted() {
    let config = ClientConfig {
        aliases: vec![alias("10.0.0.9", "Never-Seen")],
        ..ClientConfig::default()
    };
    let directory = ClientDirectory::new(&config);

    directory.identify("10.0.0.1".parse().unwrap());
    std::thread::sleep(std::time::Duration::from_millis(2));
    directory.identify("10.0.0.2".parse().unwrap());
    directory.identify("10.0.0.2".parse().unwrap());

    assert_eq!(directory.query_count("10.0.0.2".parse().unwrap()), 2);
    assert!(directory.last_seen("10.0.0.1".parse().unwrap()).is_some());

    let info = directory.info();
    assert_eq!(info.len(), 3);
    assert_eq!(info[0].ip, "10.0.0.2".parse::<std::net::IpAddr>().unwrap());
    assert_eq!(info[0].query_count, 2);
    let never = info
        .iter()
        .find(|entry| entry.name == "Never-Seen")
        .expect("alias-only client");
    assert_eq!(never.query_count, 0);
    assert_eq!(never.last_seen_ms, 0);
}

#[test]
fn lookup_name_does_not_record_activity() {
    let config = ClientConfig {
        aliases: vec![alias("10.0.0.1", "Laptop")],
        ..ClientConfig::default()
    };
    let directory = ClientDirectory::new(&config);

    assert_eq!(directory.lookup_name("10.0.0.1".parse().unwrap()), "Laptop");
    assert_eq!(directory.query_count("10.0.0.1".parse().unwrap()), 0);
}

#[test]
fn group_lookup_uses_compiled_groups() {
    let config = ClientConfig {
        groups_enabled: true,
        groups: vec![group("lan", &["10.0.0.0/8"])],
        ..ClientConfig::default()
    };
    let directory = ClientDirectory::new(&config);

    assert_eq!(directory.group("10.1.2.3".parse().unwrap()), "lan");
    assert_eq!(
        directory.group("192.168.1.1".parse().unwrap()),
        DEFAULT_GROUP
    );
}

#[test]
fn configure_reports_diagnostics_and_replaces_groups() {
    let directory = ClientDirectory::new(&ClientConfig::default());
    let config = ClientConfig {
        groups_enabled: true,
        groups: vec![group("lan", &["10.0.0.0/8", "bogus"])],
        ..ClientConfig::default()
    };

    let problems = directory.configure(&config);
    assert_eq!(problems.len(), 1);
    assert_eq!(directory.group("10.1.2.3".parse().unwrap()), "lan");
}

#[test]
fn cache_ttl_converts_to_millis() {
    assert_eq!(cache_ttl_millis(DurationValue::from_millis(1_500)), 1_500);
    assert_eq!(cache_ttl_millis(DurationValue::from_hours(1)), 3_600_000);
    assert_eq!(cache_ttl_millis(DurationValue::ZERO), DEFAULT_CACHE_TTL_MS);
    assert_eq!(cache_ttl_millis(DurationValue::from_secs(5)), 5_000);
}

#[tokio::test]
async fn reverse_lookup_disabled_returns_none() {
    let config = ClientConfig {
        enable_rdns: false,
        ..ClientConfig::default()
    };
    let directory = ClientDirectory::new(&config);

    assert_eq!(
        directory
            .resolve_reverse("192.0.2.1".parse().unwrap())
            .await,
        None
    );
}

#[tokio::test]
async fn concurrent_identify_aggregates_counts_in_background() {
    let config = ClientConfig {
        aliases: vec![alias("10.0.0.1", "Worker")],
        ..ClientConfig::default()
    };
    let directory = std::sync::Arc::new(ClientDirectory::new(&config));
    let ip: std::net::IpAddr = "10.0.0.1".parse().unwrap();

    let mut handles = Vec::new();
    for _ in 0..8 {
        let dir = std::sync::Arc::clone(&directory);
        handles.push(tokio::spawn(async move {
            for _ in 0..250 {
                assert_eq!(dir.identify(ip), "Worker");
            }
        }));
    }
    for handle in handles {
        handle.await.unwrap();
    }

    assert_eq!(directory.query_count(ip), 2_000);
    let info = directory.info();
    assert_eq!(info.len(), 1);
    assert_eq!(info[0].name, "Worker");
    assert_eq!(info[0].query_count, 2_000);
}
