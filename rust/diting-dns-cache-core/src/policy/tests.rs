//! Policy tests mirroring the Go arithmetic that was deleted with `dns_cache_policy.go`.

use super::*;

fn config(mode: TtlMode) -> Config {
    Config {
        enabled: true,
        mode,
        ..Config::default()
    }
    .normalized()
}

#[test]
fn defaults_match_the_go_normalizer() {
    let config = Config {
        enabled: true,
        mode: TtlMode::FixedTtl,
        ..Config::default()
    }
    .normalized();
    assert_eq!(config.max_ttl_seconds, 3600);
    assert_eq!(config.fixed_ttl_seconds, 3600);
    assert_eq!(config.min_ttl_seconds, 60);
    assert_eq!(config.stale_fallback_seconds, 300);
    assert_eq!(config.negative_ttl_seconds, 30);
    // An enabled cache always caches negative answers, even when the caller said no.
    assert!(config.negative_ttl_enabled);

    let disabled = Config::default().normalized();
    assert!(!disabled.negative_ttl_enabled);
}

#[test]
fn mode_names_are_ascii_lowercased() {
    assert_eq!(TtlMode::parse(b"FOLLOW_DNS_TTL"), TtlMode::FollowDnsTtl);
    assert_eq!(TtlMode::parse(b"Limit_Max_TTL"), TtlMode::LimitMaxTtl);
    assert_eq!(TtlMode::parse(b"fixed_ttl"), TtlMode::FixedTtl);
    assert_eq!(TtlMode::parse(b""), TtlMode::Default);
    assert_eq!(TtlMode::parse("跟随".as_bytes()), TtlMode::Default);
}

#[test]
fn effective_ttl_follows_the_upstream_value() {
    let config = config(TtlMode::FollowDnsTtl);
    assert_eq!(config.effective_ttl(300), 300);
    assert_eq!(config.effective_ttl(9999), 9999);
    assert_eq!(config.effective_ttl(0), 0);
}

#[test]
fn effective_ttl_caps_at_max() {
    let mut config = config(TtlMode::LimitMaxTtl);
    config.max_ttl_seconds = 60;
    assert_eq!(config.effective_ttl(3600), 60);
    assert_eq!(config.effective_ttl(30), 30);
    // The default mode behaves like the cap, exactly like the Go `default:` branch.
    assert_eq!(config.effective_ttl(3600), 60);
}

#[test]
fn effective_ttl_uses_the_fixed_value() {
    let mut config = config(TtlMode::FixedTtl);
    config.fixed_ttl_seconds = 120;
    assert_eq!(config.effective_ttl(5), 120);
    assert_eq!(config.effective_ttl(3600), 120);
}

#[test]
fn effective_ttl_applies_the_minimum_last() {
    let mut config = config(TtlMode::FollowDnsTtl);
    config.min_ttl_enabled = true;
    config.min_ttl_seconds = 30;
    assert_eq!(config.effective_ttl(5), 30);
    assert_eq!(config.effective_ttl(300), 300);
    // A zero upstream TTL is lifted to the minimum, not kept as "do not cache".
    assert_eq!(config.effective_ttl(0), 30);
}

#[test]
fn negative_ttl_uses_the_soa_when_it_fits() {
    let mut config = config(TtlMode::FollowDnsTtl);
    config.negative_ttl_seconds = 20;
    assert_eq!(config.negative_ttl(10, true), 10);
    assert_eq!(config.negative_ttl(30, true), 20);
    assert_eq!(config.negative_ttl(0, true), 20);
    assert_eq!(config.negative_ttl(10, false), 20);
}

#[test]
fn negative_ttl_clamps_to_five_and_three_hundred() {
    let mut config = config(TtlMode::FollowDnsTtl);
    config.negative_ttl_seconds = 1;
    assert_eq!(config.negative_ttl(0, false), 5);
    config.negative_ttl_seconds = 1000;
    assert_eq!(config.negative_ttl(0, false), 300);
    assert_eq!(config.negative_ttl(400, true), 300);
}

#[test]
fn flags_report_what_the_caller_caches() {
    let mut config = config(TtlMode::FollowDnsTtl);
    config.stale_fallback_enabled = true;
    let flags = config.flags();
    assert_eq!(flags & FLAG_ENABLED, FLAG_ENABLED);
    assert_eq!(flags & FLAG_STALE_FALLBACK, FLAG_STALE_FALLBACK);
    assert_eq!(flags & FLAG_NEGATIVE_TTL, FLAG_NEGATIVE_TTL);
    assert_eq!(flags & FLAG_MIN_TTL, 0);
}
