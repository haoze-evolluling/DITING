//! The two documents, checked field by field: these are the bytes the engines parse.

use super::*;

fn preset_providers() -> Vec<Provider> {
    vec![
        Provider::new(
            "preset_alidns_dns",
            "阿里云",
            Protocol::Plain,
            "",
            "223.5.5.5",
            53,
        ),
        Provider::new(
            "preset_dnspod_dns",
            "腾讯云",
            Protocol::Plain,
            "",
            "119.29.29.29",
            53,
        ),
        Provider::new(
            "preset_cloudflare_doh",
            "Cloudflare",
            Protocol::Doh,
            "https://cloudflare-dns.com/dns-query",
            "",
            53,
        ),
    ]
}

fn preset_bootstrap() -> Vec<BootstrapEntry> {
    vec![
        BootstrapEntry::new("preset_alidns", "阿里云", "223.5.5.5"),
        BootstrapEntry::new("preset_dnspod", "腾讯云", "119.29.29.29"),
        BootstrapEntry::new("preset_volcengine", "火山", "180.184.1.1"),
    ]
}

fn settings() -> TunnelSettings {
    TunnelSettings {
        mode_raw: "single".to_string(),
        selected_provider_id: "preset_alidns_dns".to_string(),
        smart_prediction_provider_ids: Vec::new(),
        parallel_race_provider_ids: Vec::new(),
        primary_backup_provider_ids: Vec::new(),
        user_providers_json: None,
        bootstrap_enabled: true,
        bootstrap_preset_ids: vec![
            "preset_alidns".to_string(),
            "preset_dnspod".to_string(),
            "preset_volcengine".to_string(),
        ],
        bootstrap_custom_json: None,
        block_response_mode: "nxdomain".to_string(),
        cache: CacheInput {
            enabled: true,
            mode: "limit_max_ttl".to_string(),
            max_ttl_seconds: 3600,
            fixed_ttl_seconds: 3600,
            min_ttl_enabled: false,
            min_ttl_seconds: 60,
            stale_fallback_enabled: false,
            stale_fallback_seconds: 300,
        },
        dynamic: DynamicInput {
            enabled: false,
            request_threshold: 5,
            window_seconds: 60,
            nxdomain_seconds: 300,
        },
    }
}

fn document_of(config: &TunnelConfig) -> serde_json::Value {
    serde_json::from_str(&config.document).expect("document is JSON")
}

#[test]
fn default_single_mode_picks_the_selected_plain_provider() {
    let config = build_tunnel(&settings(), &preset_providers(), &preset_bootstrap());
    assert_eq!(config.mode, "single");
    assert_eq!(config.providers.len(), 1);
    assert_eq!(config.providers[0].id, "preset_alidns_dns");
    let json = document_of(&config);
    assert_eq!(json["mode"], "single");
    assert_eq!(json["blockResponse"], "NXDOMAIN");
    assert_eq!(
        json["providers"],
        serde_json::json!([{
            "id": "preset_alidns_dns",
            "protocol": "PLAIN",
            "server": "223.5.5.5:53",
            "url": ""
        }])
    );
    assert_eq!(
        json["cache"],
        serde_json::json!({
            "enabled": true,
            "mode": "limit_max_ttl",
            "maxTtlSeconds": 3600,
            "fixedTtlSeconds": 3600,
            "minTtlEnabled": false,
            "minTtlSeconds": 60,
            "staleFallbackEnabled": false,
            "staleFallbackSeconds": 300,
            "negativeTtlEnabled": true,
            "negativeTtlSeconds": 30
        })
    );
    assert_eq!(
        json["dynamicResponse"],
        serde_json::json!({
            "enabled": false,
            "requestThreshold": 5,
            "windowSeconds": 60,
            "nxDomainDurationSeconds": 300
        })
    );
}

#[test]
fn doh_provider_has_no_server_and_keeps_the_url() {
    let mut input = settings();
    input.selected_provider_id = "preset_cloudflare_doh".to_string();
    let json = document_of(&build_tunnel(
        &input,
        &preset_providers(),
        &preset_bootstrap(),
    ));
    assert_eq!(
        json["providers"],
        serde_json::json!([{
            "id": "preset_cloudflare_doh",
            "protocol": "DOH",
            "server": "",
            "url": "https://cloudflare-dns.com/dns-query"
        }])
    );
}

#[test]
fn race_modes_use_their_list_and_fall_back_below_two() {
    let mut input = settings();
    input.mode_raw = "parallel_race".to_string();
    let raced = build_tunnel(&input, &preset_providers(), &preset_bootstrap());
    let ids: Vec<&str> = raced
        .providers
        .iter()
        .map(|provider| provider.id.as_str())
        .collect();
    assert_eq!(ids, ["preset_alidns_dns", "preset_dnspod_dns"]);
    assert_eq!(raced.mode, "parallel_race");

    input.parallel_race_provider_ids = vec!["preset_cloudflare_doh".to_string()];
    let single = build_tunnel(&input, &preset_providers(), &preset_bootstrap());
    assert_eq!(single.providers.len(), 1);
    assert_eq!(single.providers[0].id, "preset_alidns_dns");
    assert_eq!(single.mode, "parallel_race");
}

#[test]
fn an_unknown_mode_is_single() {
    let mut input = settings();
    input.mode_raw = "turbo".to_string();
    let config = build_tunnel(&input, &preset_providers(), &preset_bootstrap());
    assert_eq!(config.mode, "single");
    assert_eq!(config.providers.len(), 1);
}

#[test]
fn custom_providers_join_the_catalog_and_win_on_a_duplicate_id() {
    let mut input = settings();
    input.user_providers_json = Some(
        r#"[{"id":"user_1","name":"自建 DoT","protocol":"DOT","url":"","host":"dot.example","port":853},
            {"id":"preset_alidns_dns","name":"覆盖","protocol":"DOT","url":"","host":"o.example","port":853}]"#
            .to_string(),
    );
    let config = build_tunnel(&input, &preset_providers(), &preset_bootstrap());
    assert_eq!(config.providers[0].name, "覆盖");
    assert_eq!(config.providers[0].host_port(), "o.example:853");

    input.selected_provider_id = "user_1".to_string();
    let custom = build_tunnel(&input, &preset_providers(), &preset_bootstrap());
    assert_eq!(custom.providers[0].id, "user_1");
}

#[test]
fn unknown_selected_id_falls_back_to_the_preset_default() {
    let mut input = settings();
    input.selected_provider_id = "gone".to_string();
    let config = build_tunnel(&input, &preset_providers(), &preset_bootstrap());
    assert_eq!(config.providers[0].id, "preset_alidns_dns");
}

#[test]
fn bootstrap_keeps_only_selected_presets_and_enabled_custom_rows() {
    let mut input = settings();
    input.bootstrap_custom_json = Some(
        r#"[{"id":"","name":"","ip":"9.9.9.9","enabled":true},
            {"id":"off","name":"关","ip":"1.2.3.4","enabled":false},
            {"id":"c1","name":"自建","ip":"5.6.7.8"}]"#
            .to_string(),
    );
    let config = build_tunnel(&input, &preset_providers(), &preset_bootstrap());
    let ips: Vec<&str> = config
        .bootstrap
        .iter()
        .map(|entry| entry.ip.as_str())
        .collect();
    assert_eq!(
        ips,
        [
            "223.5.5.5",
            "119.29.29.29",
            "180.184.1.1",
            "9.9.9.9",
            "5.6.7.8"
        ]
    );
    assert_eq!(config.bootstrap[3].id, "custom_9.9.9.9");
    assert_eq!(config.bootstrap[3].name, "9.9.9.9");

    input.bootstrap_enabled = false;
    let disabled = build_tunnel(&input, &preset_providers(), &preset_bootstrap());
    assert!(disabled.bootstrap.is_empty());
    let json = document_of(&disabled);
    assert_eq!(
        json["bootstrap"],
        serde_json::json!({"enabled": false, "ips": []})
    );
}

#[test]
fn clamps_and_block_response_are_applied() {
    let mut input = settings();
    input.block_response_mode = "zero_address".to_string();
    input.cache.max_ttl_seconds = 1;
    input.cache.fixed_ttl_seconds = 999_999;
    input.cache.min_ttl_seconds = 0;
    input.cache.stale_fallback_seconds = 1;
    input.dynamic = DynamicInput {
        enabled: true,
        request_threshold: 500,
        window_seconds: 1,
        nxdomain_seconds: 99_999,
    };
    let json = document_of(&build_tunnel(
        &input,
        &preset_providers(),
        &preset_bootstrap(),
    ));
    assert_eq!(json["blockResponse"], "CUSTOM_IP");
    assert_eq!(json["cache"]["maxTtlSeconds"], 30);
    assert_eq!(json["cache"]["fixedTtlSeconds"], 86400);
    assert_eq!(json["cache"]["minTtlSeconds"], 30);
    assert_eq!(json["cache"]["staleFallbackSeconds"], 30);
    assert_eq!(
        json["dynamicResponse"],
        serde_json::json!({
            "enabled": true,
            "requestThreshold": 100,
            "windowSeconds": 10,
            "nxDomainDurationSeconds": 3600
        })
    );
}

fn preset_upstreams() -> Vec<ServerUpstream> {
    vec![
        ServerUpstream::new(
            "preset_alidns_dns",
            "阿里云",
            Protocol::Plain,
            "223.5.5.5",
            53,
        ),
        ServerUpstream::new(
            "preset_cloudflare_doh",
            "Cloudflare",
            Protocol::Doh,
            "https://cloudflare-dns.com/dns-query",
            443,
        ),
    ]
}

fn server_settings() -> ServerSettings {
    ServerSettings {
        resolution_mode_raw: "single".to_string(),
        selected_upstream_id: "preset_alidns_dns".to_string(),
        smart_prediction_provider_ids: Vec::new(),
        parallel_race_provider_ids: Vec::new(),
        primary_backup_provider_ids: Vec::new(),
        port: 1053,
        ad_block_enabled: false,
        cache_preset_raw: String::new(),
        cache_enabled: true,
        block_response_mode: "nxdomain".to_string(),
        dynamic: DynamicInput {
            enabled: false,
            request_threshold: 5,
            window_seconds: 60,
            nxdomain_seconds: 300,
        },
        custom_upstreams_json: None,
    }
}

#[test]
fn server_document_defaults() {
    let config = build_server(&server_settings(), &preset_upstreams()).expect("config");
    assert_eq!(config.port, 1053);
    assert_eq!(config.mode, "single");
    assert_eq!(config.providers.len(), 1);
    assert_eq!(config.providers[0].id, "preset_alidns_dns");
    let json: serde_json::Value = serde_json::from_str(&config.document).expect("json");
    assert_eq!(json["mode"], "single");
    assert_eq!(json["blockResponse"], "NXDOMAIN");
    assert_eq!(
        json["bootstrap"],
        serde_json::json!({"enabled": false, "ips": []})
    );
    assert_eq!(
        json["providers"],
        serde_json::json!([{
            "id": "preset_alidns_dns",
            "protocol": "PLAIN",
            "server": "223.5.5.5:53",
            "url": ""
        }])
    );
    let cache = &json["cache"];
    assert_eq!(cache["enabled"], true);
    assert_eq!(cache["mode"], "limit_max_ttl");
    assert_eq!(cache["minTtlEnabled"], true);
    assert_eq!(cache["negativeTtlSeconds"], 30);
}

#[test]
fn server_race_mode_uses_the_picked_list_in_order() {
    let mut input = server_settings();
    input.resolution_mode_raw = "primary_backup".to_string();
    input.primary_backup_provider_ids = vec![
        "preset_cloudflare_doh".to_string(),
        "preset_alidns_dns".to_string(),
    ];
    let config = build_server(&input, &preset_upstreams()).expect("config");
    assert_eq!(config.mode, "primary_backup");
    let ids: Vec<&str> = config.providers.iter().map(|row| row.id.as_str()).collect();
    assert_eq!(ids, ["preset_cloudflare_doh", "preset_alidns_dns"]);
    let json: serde_json::Value = serde_json::from_str(&config.document).expect("json");
    assert_eq!(json["mode"], "primary_backup");
    assert_eq!(json["providers"].as_array().expect("providers").len(), 2);
}

#[test]
fn server_race_mode_falls_back_to_the_selected_upstream() {
    let mut input = server_settings();
    input.resolution_mode_raw = "parallel_race".to_string();
    // Nothing configured: the race list defaults to two presets, but only one exists here.
    let config = build_server(&input, &preset_upstreams()).expect("config");
    assert_eq!(config.mode, "parallel_race");
    assert_eq!(config.providers.len(), 1);
    assert_eq!(config.providers[0].id, "preset_alidns_dns");
}

#[test]
fn server_document_uses_the_selected_custom_doh_and_preset_cache() {
    let mut input = server_settings();
    input.selected_upstream_id = "custom_doh".to_string();
    input.cache_preset_raw = "conservative".to_string();
    input.custom_upstreams_json = Some(
        r#"[{"id":"custom_doh","name":"自定义 DoH","address":"https://dns.example/dns-query","port":443,"protocol":"DOH"},
            {"id":"custom_bad","name":"坏","address":"http://x","port":443,"protocol":"DOH"}]"#
            .to_string(),
    );
    let config = build_server(&input, &preset_upstreams()).expect("config");
    assert_eq!(config.providers[0].id, "custom_doh");
    let json: serde_json::Value = serde_json::from_str(&config.document).expect("json");
    assert_eq!(
        json["providers"],
        serde_json::json!([{
            "id": "custom_doh",
            "protocol": "DOH",
            "server": "",
            "url": "https://dns.example/dns-query"
        }])
    );
    assert_eq!(json["cache"]["mode"], "follow_dns_ttl");
    assert_eq!(json["cache"]["minTtlEnabled"], false);
    assert_eq!(json["cache"]["negativeTtlSeconds"], 15);
}

#[test]
fn server_falls_back_when_the_selected_upstream_is_gone() {
    let mut input = server_settings();
    input.selected_upstream_id = "custom_gone".to_string();
    let config = build_server(&input, &preset_upstreams()).expect("config");
    assert_eq!(config.providers[0].id, "preset_alidns_dns");
}

#[test]
fn server_without_any_catalog_is_rejected() {
    assert!(build_server(&server_settings(), &[]).is_none());
}
