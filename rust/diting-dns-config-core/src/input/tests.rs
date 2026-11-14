//! The decoders, checked against payloads the Dart side actually writes.

use super::*;
use crate::wire::Writer;

fn tunnel_payload() -> Vec<u8> {
    let mut writer = Writer::new();
    // bootstrapEnabled | cacheEnabled | cacheMinTtlEnabled | cacheStaleEnabled | dynamicEnabled
    writer.u8(0b1_1111);
    writer.string("parallel_race");
    writer.string("preset_alidns_dns");
    writer.strings(&["preset_google_dns".to_string()]);
    writer.strings(&[
        "preset_alidns_dns".to_string(),
        "preset_dnspod_dns".to_string(),
    ]);
    writer.strings(&[]);
    writer.opt_string(None);
    writer.strings(&["preset_alidns".to_string()]);
    writer.opt_string(Some("[]"));
    writer.string("refused");
    writer.string("follow_dns_ttl");
    writer.i32(600);
    writer.i32(3600);
    writer.i32(30);
    writer.i32(300);
    writer.i32(7);
    writer.i32(120);
    writer.i32(600);
    writer.finish()
}

#[test]
fn tunnel_settings_decode_every_field() {
    let bytes = tunnel_payload();
    let mut reader = Reader::new(&bytes);
    let settings = tunnel_settings(&mut reader).expect("settings");
    assert!(settings.bootstrap_enabled);
    assert_eq!(settings.mode_raw, "parallel_race");
    assert_eq!(settings.selected_provider_id, "preset_alidns_dns");
    assert_eq!(
        settings.smart_prediction_provider_ids,
        ["preset_google_dns"]
    );
    assert_eq!(
        settings.parallel_race_provider_ids,
        ["preset_alidns_dns", "preset_dnspod_dns"]
    );
    assert!(settings.primary_backup_provider_ids.is_empty());
    assert_eq!(settings.user_providers_json, None);
    assert_eq!(settings.bootstrap_preset_ids, ["preset_alidns"]);
    assert_eq!(settings.bootstrap_custom_json.as_deref(), Some("[]"));
    assert_eq!(settings.block_response_mode, "refused");
    assert!(settings.cache.enabled);
    assert_eq!(settings.cache.mode, "follow_dns_ttl");
    assert_eq!(settings.cache.max_ttl_seconds, 600);
    assert!(settings.cache.min_ttl_enabled);
    assert!(settings.cache.stale_fallback_enabled);
    assert_eq!(settings.cache.stale_fallback_seconds, 300);
    assert!(settings.dynamic.enabled);
    assert_eq!(settings.dynamic.request_threshold, 7);
    assert_eq!(settings.dynamic.window_seconds, 120);
    assert_eq!(settings.dynamic.nxdomain_seconds, 600);
}

#[test]
fn flags_carry_the_booleans() {
    let mut writer = Writer::new();
    writer.u8(0);
    writer.string("single");
    writer.string("preset_alidns_dns");
    writer.strings(&[]);
    writer.strings(&[]);
    writer.strings(&[]);
    writer.opt_string(None);
    writer.strings(&[]);
    writer.opt_string(None);
    writer.string("nxdomain");
    writer.string("limit_max_ttl");
    writer.i32(3600);
    writer.i32(3600);
    writer.i32(60);
    writer.i32(300);
    writer.i32(5);
    writer.i32(60);
    writer.i32(300);
    let bytes = writer.finish();
    let mut reader = Reader::new(&bytes);
    let settings = tunnel_settings(&mut reader).expect("settings");
    assert!(!settings.bootstrap_enabled);
    assert!(!settings.cache.enabled);
    assert!(!settings.cache.min_ttl_enabled);
    assert!(!settings.cache.stale_fallback_enabled);
    assert!(!settings.dynamic.enabled);
}

#[test]
fn server_settings_decode() {
    let mut writer = Writer::new();
    writer.u8(0b111);
    writer.string("primary_backup");
    writer.string("custom_doh");
    writer.strings(&["preset_alidns_dns".to_string()]);
    writer.strings(&["preset_alidns_dns".to_string()]);
    writer.strings(&[
        "preset_cloudflare_doh".to_string(),
        "preset_alidns_dns".to_string(),
    ]);
    writer.i32(2053);
    writer.string("high_hit_rate");
    writer.string("nodata");
    writer.i32(9);
    writer.i32(30);
    writer.i32(120);
    writer.opt_string(Some("[]"));
    writer.i32(20);
    writer.i32(40);
    writer.i32(24);
    writer.i32(56);
    writer.string("192.168.0.1,10.0.0.0/8");
    let bytes = writer.finish();
    let mut reader = Reader::new(&bytes);
    let settings = server_settings(&mut reader).expect("settings");
    assert!(settings.ad_block_enabled);
    assert!(settings.cache_enabled);
    assert!(settings.dynamic.enabled);
    assert_eq!(settings.resolution_mode_raw, "primary_backup");
    assert_eq!(settings.selected_upstream_id, "custom_doh");
    assert_eq!(
        settings.smart_prediction_provider_ids,
        ["preset_alidns_dns"]
    );
    assert_eq!(settings.parallel_race_provider_ids, ["preset_alidns_dns"]);
    assert_eq!(
        settings.primary_backup_provider_ids,
        ["preset_cloudflare_doh", "preset_alidns_dns"]
    );
    assert_eq!(settings.port, 2053);
    assert_eq!(settings.cache_preset_raw, "high_hit_rate");
    assert_eq!(settings.block_response_mode, "nodata");
    assert_eq!(settings.dynamic.request_threshold, 9);
    assert_eq!(settings.dynamic.window_seconds, 30);
    assert_eq!(settings.dynamic.nxdomain_seconds, 120);
    assert_eq!(settings.custom_upstreams_json.as_deref(), Some("[]"));
    assert!(!settings.rate_limit.enabled);
    assert_eq!(settings.rate_limit.rate, 20);
    assert_eq!(settings.rate_limit.burst, 40);
    assert_eq!(settings.rate_limit.ipv4_prefix, 24);
    assert_eq!(settings.rate_limit.ipv6_prefix, 56);
    assert_eq!(settings.rate_limit.exempt, ["192.168.0.1", "10.0.0.0/8"]);
}

#[test]
fn record_lists_decode_and_truncation_is_rejected() {
    let mut writer = Writer::new();
    writer.u32(1);
    writer.string("preset_alidns_dns");
    writer.string("阿里云");
    writer.string("DNS");
    writer.string("");
    writer.string("223.5.5.5");
    writer.i32(53);
    let bytes = writer.finish();
    let mut reader = Reader::new(&bytes);
    let providers = read_providers(&mut reader).expect("providers");
    assert_eq!(providers[0].protocol, Protocol::Plain);

    let truncated = &bytes[..bytes.len() - 2];
    let mut reader = Reader::new(truncated);
    assert!(read_providers(&mut reader).is_none());
}

#[test]
fn an_unknown_protocol_spelling_reads_as_plain() {
    let mut writer = Writer::new();
    writer.u32(1);
    writer.string("x");
    writer.string("X");
    writer.string("QUIC");
    writer.string("");
    writer.string("1.1.1.1");
    writer.i32(53);
    let bytes = writer.finish();
    let mut reader = Reader::new(&bytes);
    let providers = read_providers(&mut reader).expect("providers");
    assert_eq!(providers[0].protocol, Protocol::Plain);
}
