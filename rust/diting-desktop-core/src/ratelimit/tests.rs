use std::net::IpAddr;
use std::time::Duration;

use super::*;

fn config() -> RateLimitConfig {
    RateLimitConfig {
        enabled: true,
        rate: 50.0,
        burst: 2,
        ipv4_prefix: 32,
        ipv6_prefix: 128,
        exempt_ips: vec!["127.0.0.1".to_string(), "::1".to_string()],
    }
}

fn ip(text: &str) -> IpAddr {
    text.parse().expect("valid test address")
}

#[test]
fn disabled_limiter_allows_everything() {
    let limiter = RateLimiter::new(&RateLimitConfig::default());
    assert!(!limiter.enabled());
    assert!(limiter.allow(Some(ip("10.0.0.1"))));
    assert!(limiter.allow(None));
}

#[test]
fn burst_is_consumed_then_rejected() {
    let limiter = RateLimiter::new(&config());
    let client = ip("10.0.0.1");

    assert!(limiter.allow(Some(client)));
    assert!(limiter.allow(Some(client)));
    assert!(!limiter.allow(Some(client)));

    assert_eq!(limiter.info().buckets, 1);
}

#[test]
fn exempt_ips_and_missing_addresses_bypass_the_limiter() {
    let mut settings = config();
    settings.burst = 1;
    let limiter = RateLimiter::new(&settings);

    let loopback = ip("127.0.0.1");
    assert!(limiter.is_exempt(Some(loopback)));
    assert!(limiter.is_exempt(None));
    assert!(!limiter.is_exempt(Some(ip("10.0.0.1"))));

    assert!(limiter.allow(Some(loopback)));
    assert!(limiter.allow(Some(loopback)));
    assert!(limiter.allow(None));

    let other = ip("10.0.0.1");
    assert!(limiter.allow(Some(other)));
    assert!(!limiter.allow(Some(other)));
}

#[test]
fn tokens_refill_over_time() {
    let mut settings = config();
    settings.rate = 1_000.0;
    settings.burst = 1;
    let limiter = RateLimiter::new(&settings);
    let client = ip("10.0.0.1");

    assert!(limiter.allow(Some(client)));
    assert!(!limiter.allow(Some(client)));

    std::thread::sleep(Duration::from_millis(20));
    assert!(limiter.allow(Some(client)));
}

#[test]
fn prefix_aggregation_shares_one_bucket() {
    let mut settings = config();
    settings.burst = 1;
    settings.ipv4_prefix = 24;
    settings.exempt_ips.clear();
    let limiter = RateLimiter::new(&settings);

    assert!(limiter.allow(Some(ip("10.0.0.1"))));
    assert!(!limiter.allow(Some(ip("10.0.0.2"))));
    assert!(limiter.allow(Some(ip("10.0.1.1"))));
}

#[test]
fn configuration_round_trips_and_reconfigures() {
    let settings = config();
    let limiter = RateLimiter::new(&settings);
    assert_eq!(limiter.config(), settings);
    assert!(limiter.enabled());

    let disabled = RateLimitConfig {
        enabled: false,
        ..settings
    };
    limiter.configure(&disabled);
    assert!(!limiter.enabled());
    assert_eq!(limiter.config(), disabled);
    assert!(limiter.allow(Some(ip("10.0.0.1"))));
}

#[test]
fn ipv6_exemption_works() {
    let mut settings = config();
    settings.burst = 1;
    settings.exempt_ips = vec!["::1".to_string()];
    let limiter = RateLimiter::new(&settings);

    let loopback = ip("::1");
    assert!(limiter.is_exempt(Some(loopback)));
    assert!(limiter.allow(Some(loopback)));
    assert!(limiter.allow(Some(loopback)));
}
