use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{json, Value};

use super::*;

fn temp_path(name: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    std::env::temp_dir().join(format!(
        "diting-desktop-api-{name}-{}-{nanos}",
        std::process::id()
    ))
}

#[test]
fn defaults_match_the_go_default_config() {
    let config = Config::default();

    assert_eq!(
        config.dns.udp_addresses,
        vec!["127.0.0.1:53".to_string(), "[::1]:53".to_string()]
    );
    assert_eq!(config.dns.tcp_addresses, config.dns.udp_addresses);
    assert_eq!(config.dns.read_timeout, DurationValue::from_secs(5));
    assert_eq!(config.dns.write_timeout, DurationValue::from_secs(5));
    assert!(config.dns.enable_ede);
    assert!(config.dns.block_private_ptr);
    assert_eq!(config.dns.edns_padding, 128);
    assert_eq!(config.dns.block_any_mode, "notimp");

    assert_eq!(config.upstream.mode, "primary_backup");
    assert_eq!(config.upstream.edns_padding, 128);
    assert_eq!(config.upstream.providers.len(), 2);
    assert_eq!(config.upstream.providers[0].protocol, "DOT");
    assert_eq!(config.upstream.providers[0].server, "dns.alidns.com:853");
    assert!(config.upstream.bootstrap.enabled);
    assert_eq!(config.upstream.bootstrap.servers.len(), 2);
    assert_eq!(config.upstream.fallback_on_rcode, None);

    assert_eq!(config.ipc.listen_address, "127.0.0.1:15353");
    assert_eq!(config.cache.max_entries, 4096);
    assert_eq!(config.cache.mode, "limit_max_ttl");
    assert!(config.cache.optimistic);
    assert_eq!(config.cache.prefetch_threshold, 5);
    assert_eq!(config.cache.prefetch_before_expiry_ms, 30_000);

    assert_eq!(config.filter.lists.len(), 1);
    assert_eq!(config.filter.lists[0].id, "adguard-dns-filter");
    assert_eq!(config.filter.block_mode, "null_ip");
    assert_eq!(config.filter.update_interval_hours, 24);
    assert_eq!(
        config.filter.bogus_nx_domain_networks,
        vec![
            "0.0.0.0/8".to_string(),
            "::/128".to_string(),
            "127.0.0.0/8".to_string(),
            "::1/128".to_string()
        ]
    );

    assert!(config.hosts.enabled);
    assert_eq!(config.hosts.ttl, 60);
    assert!(config.rebind.enabled);
    assert_eq!(
        config.rebind.allowed_domains,
        vec![
            "localhost",
            ".local",
            ".lan",
            ".home.arpa",
            "in-addr.arpa",
            "ip6.arpa"
        ]
    );
    assert!(config.access.allowed_clients.is_empty());
    assert_eq!(config.rate_limit.rate, 50.0);
    assert_eq!(config.rate_limit.burst, 100);
    assert_eq!(
        config.rate_limit.exempt_ips,
        vec!["127.0.0.1".to_string(), "::1".to_string()]
    );
    assert_eq!(config.dns64.prefixes, vec!["64:ff9b::/96".to_string()]);
    assert_eq!(config.rewrite.ttl, 60);
    assert_eq!(config.zone.ttl, 300);
    assert_eq!(config.safe_search.ttl, 300);
    assert_eq!(config.safe_browsing.timeout_ms, 3000);
    assert_eq!(config.safe_browsing.cache_ttl_seconds, 600);

    assert!(!config.encrypted.enabled);
    assert_eq!(config.encrypted.cert.source, "self_signed");
    assert_eq!(config.encrypted.cert.key_type, "ecdsa");
    assert_eq!(config.encrypted.cert.valid_days, 825);
    assert_eq!(config.encrypted.dot_port, 853);
    assert_eq!(config.encrypted.doh_port, 443);
    assert_eq!(config.encrypted.doh_path, "/dns-query");
    assert_eq!(config.encrypted.server_name, "dns.lan");

    assert!(config.client.enabled);
    assert!(config.client.enable_rdns);
    assert_eq!(config.client.cache_ttl, DurationValue::from_hours(1));
    assert!(config.ecs.enabled);
    assert!(config.ecs.strip_ecs);

    assert!(config.query_log.enabled);
    assert_eq!(config.query_log.max_entries, 10_000);
    assert_eq!(
        config.query_log.data_dir,
        paths::default_query_log_dir().to_string_lossy()
    );

    assert!(config.web.enabled);
    assert_eq!(config.web.listen_port, 15353);
    assert_eq!(config.web.session_timeout, DurationValue::from_hours(168));
    assert_eq!(config.web.background.kind, "none");
    assert_eq!(config.web.background.opacity, 40);
}

#[test]
fn roundtrip_representative_config() {
    let json = r#"{
        "dns": {
            "udpAddresses": ["127.0.0.1:5353"],
            "tcpAddresses": [],
            "readTimeout": "2s",
            "writeTimeout": 3000000000,
            "allowLAN": true,
            "enableEDE": false,
            "blockANY": true,
            "blockANYMode": "rfc8482",
            "unknownDnsField": true
        },
        "upstream": {
            "mode": "backup",
            "ednsPadding": 64,
            "providers": [{"id": "p1", "protocol": "DOT", "server": "1.1.1.1:853"}],
            "bootstrap": {
                "enabled": true,
                "servers": [{"id": "bs", "name": "n", "address": "8.8.8.8:53"}]
            },
            "conditionalRoutes": {"lan": "tls://192.168.1.1"},
            "fallbackOnRcode": []
        },
        "cache": {"maxEntries": 512, "persistEnabled": true, "persistIntervalSeconds": 10},
        "filter": {
            "enabled": false,
            "blockMode": "nxdomain",
            "customRules": ["||ads.example^"],
            "bogusNxDomainNetworks": [" 10.0.0.0/8 ", "10.0.0.0/8", "::1/128"],
            "schedules": [{
                "id": "s1",
                "name": "night",
                "enabled": true,
                "weekdays": ["Mon"],
                "start": "22:00",
                "end": "06:00"
            }]
        },
        "web": {
            "sessionTimeout": "24h",
            "background": {"type": "url", "url": "https://example/x.png", "opacity": 150, "blur": -2}
        },
        "client": {
            "cacheTTL": 3600000000000,
            "aliases": [{"ip": "192.168.1.2", "name": "laptop"}],
            "groupsEnabled": true,
            "groups": [{"id": "kids", "name": "Kids", "enabled": true, "clients": ["192.168.1.0/24"]}]
        },
        "querylog": {"maxEntries": 999999, "retentionDays": 999, "dataDir": "  "},
        "unknownTop": 1
    }"#;

    let mut config: Config = serde_json::from_str(json).unwrap();
    config.normalize();

    assert_eq!(config.dns.read_timeout, DurationValue::from_secs(2));
    assert_eq!(config.dns.write_timeout, DurationValue::from_secs(3));
    assert!(config.dns.allow_lan);
    assert!(!config.dns.enable_ede);
    // Container-level defaults fill fields the JSON omitted.
    assert!(config.dns.block_private_ptr);
    assert_eq!(config.dns.block_any_mode, "rfc8482");
    assert!(config.dns.tcp_addresses.is_empty());

    // `normalizeConfig` does not canonicalize the scheduling mode; only empty values are filled.
    assert_eq!(config.upstream.mode, "backup");
    assert_eq!(config.upstream.providers.len(), 1);
    assert_eq!(config.upstream.bootstrap.servers.len(), 1);
    assert_eq!(
        config
            .upstream
            .conditional_routes
            .get("lan")
            .map(String::as_str),
        Some("tls://192.168.1.1")
    );
    // Empty list is preserved, distinct from `null`.
    assert_eq!(config.upstream.fallback_on_rcode, Some(Vec::new()));

    assert_eq!(config.cache.max_entries, 512);
    // Persist interval is clamped to the 30s minimum.
    assert_eq!(config.cache.persist_interval_seconds, 30);
    assert_eq!(config.cache.max_ttl_seconds, 3600);

    assert!(!config.filter.enabled);
    assert_eq!(config.filter.block_mode, "nxdomain");
    assert_eq!(
        config.filter.custom_rules,
        vec!["||ads.example^".to_string()]
    );
    assert_eq!(
        config.filter.bogus_nx_domain_networks,
        vec!["10.0.0.0/8".to_string(), "::1/128".to_string()]
    );
    assert_eq!(config.filter.schedules.len(), 1);
    assert_eq!(config.filter.schedules[0].weekdays, vec!["Mon".to_string()]);
    assert_eq!(config.filter.lists.len(), 1);
    assert_eq!(
        config.filter.data_dir,
        paths::default_filter_dir().to_string_lossy()
    );

    assert_eq!(config.web.session_timeout, DurationValue::from_hours(24));
    assert_eq!(config.web.background.opacity, 100);
    assert_eq!(config.web.background.blur, 0);
    assert_eq!(config.web.listen_port, 15353);
    assert_eq!(config.web.username, "admin");

    assert_eq!(config.client.cache_ttl, DurationValue::from_hours(1));
    assert_eq!(config.client.aliases.len(), 1);
    assert_eq!(config.client.groups.len(), 1);
    assert_eq!(config.client.groups[0].id, "kids");
    assert_eq!(
        config.client.groups[0].clients,
        vec!["192.168.1.0/24".to_string()]
    );

    assert_eq!(config.query_log.max_entries, 200_000);
    assert_eq!(config.query_log.retention_days, 365);
    assert_eq!(
        config.query_log.data_dir,
        paths::default_query_log_dir().to_string_lossy()
    );

    // Missing top-level sections keep their Go defaults.
    assert!(config.hosts.enabled);
    assert!(config.rebind.enabled);

    let encoded = serde_json::to_string_pretty(&config).unwrap();
    let decoded: Config = serde_json::from_str(&encoded).unwrap();
    assert_eq!(decoded, config);

    let value: Value = serde_json::from_str(&encoded).unwrap();
    assert_eq!(value["dns"]["readTimeout"], json!(2_000_000_000i64));
    assert_eq!(value["dns"]["writeTimeout"], json!(3_000_000_000i64));
    assert_eq!(value["web"]["sessionTimeout"], json!(86_400_000_000_000i64));
    assert_eq!(value["client"]["cacheTTL"], json!(3_600_000_000_000i64));
    assert_eq!(value["querylog"]["maxEntries"], json!(200_000));
    assert!(value.get("unknownTop").is_none());
    assert!(value["dns"].get("unknownDnsField").is_none());
}

#[test]
fn unknown_fields_are_tolerated() {
    let config: Config =
        serde_json::from_str(r#"{"futureSection": {"x": 1}, "dns": {"futureField": [1, 2, 3]}}"#)
            .unwrap();
    assert_eq!(config.dns.read_timeout, DurationValue::from_secs(5));
}

#[test]
fn explicit_nulls_fall_back_to_defaults() {
    let mut config: Config = serde_json::from_str(
        r#"{
            "dns": {"readTimeout": null, "udpAddresses": null, "tcpAddresses": null},
            "upstream": {"providers": null, "fallbackOnRcode": null, "fallbackOnError": null},
            "filter": {"lists": null, "customRules": null, "schedules": null},
            "client": {"cacheTTL": null, "groups": null}
        }"#,
    )
    .unwrap();
    config.normalize();

    assert_eq!(config.dns.read_timeout, DurationValue::from_secs(5));
    assert_eq!(config.dns.udp_addresses.len(), 2);
    assert_eq!(config.dns.tcp_addresses.len(), 2);
    assert!(config.upstream.providers.is_empty());
    assert_eq!(config.upstream.fallback_on_rcode, None);
    assert_eq!(config.upstream.fallback_on_error, None);
    assert_eq!(config.filter.lists.len(), 1);
    assert!(config.filter.custom_rules.is_empty());
    assert!(config.filter.schedules.is_empty());
    assert_eq!(config.client.cache_ttl, DurationValue::from_hours(1));
    assert!(config.client.groups.is_empty());
}

#[test]
fn fallback_on_rcode_preserves_null_versus_empty() {
    let missing: Config = serde_json::from_str(r#"{"upstream": {}}"#).unwrap();
    assert_eq!(missing.upstream.fallback_on_rcode, None);
    let encoded = serde_json::to_value(&missing).unwrap();
    assert_eq!(encoded["upstream"]["fallbackOnRcode"], Value::Null);

    let empty: Config = serde_json::from_str(r#"{"upstream": {"fallbackOnRcode": []}}"#).unwrap();
    assert_eq!(empty.upstream.fallback_on_rcode, Some(Vec::new()));
    let encoded = serde_json::to_value(&empty).unwrap();
    assert_eq!(encoded["upstream"]["fallbackOnRcode"], json!([]));
}

#[test]
fn missing_file_returns_default_config() {
    let path = temp_path("missing");
    let config = load_config(&path).unwrap();
    assert_eq!(config.dns.udp_addresses.len(), 2);
    assert_eq!(config.upstream.providers.len(), 2);
}

#[test]
fn malformed_file_returns_error() {
    let path = temp_path("malformed");
    fs::write(&path, b"{not json").unwrap();
    let error = load_config(&path).unwrap_err();
    assert_eq!(error.kind(), std::io::ErrorKind::InvalidData);
    let _ = fs::remove_file(path);
}

#[test]
fn save_and_load_roundtrip() {
    let path = temp_path("save").with_extension("json");
    let mut config = Config::default();
    config.dns.read_timeout = DurationValue::from_secs(2);
    config.web.session_timeout = DurationValue::from_hours(48);
    config.client.groups_enabled = true;
    config.client.groups.push(ClientGroup {
        id: "g".to_string(),
        name: "Group".to_string(),
        enabled: true,
        clients: vec!["10.0.0.0/8".to_string()],
        ..ClientGroup::default()
    });
    config.normalize();

    save_config(&path, &config).unwrap();
    let loaded = load_config(&path).unwrap();
    assert_eq!(loaded, config);

    let raw: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    assert_eq!(raw["dns"]["readTimeout"], json!(2_000_000_000i64));
    assert_eq!(raw["web"]["sessionTimeout"], json!(172_800_000_000_000i64));

    let _ = fs::remove_file(path);
}

#[test]
fn normalization_is_idempotent() {
    let mut config = Config::default();
    config.filter.schedules.push(BlockingSchedule {
        id: String::new(),
        name: String::new(),
        enabled: true,
        weekdays: vec!["mon".to_string()],
        start: "01:00".to_string(),
        end: "02:00".to_string(),
    });
    config.normalize();
    let once = config.clone();
    config.normalize();
    assert_eq!(once, config);
}
