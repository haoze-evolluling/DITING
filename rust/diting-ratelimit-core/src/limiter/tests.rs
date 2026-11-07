use super::*;

fn address(text: &str) -> Option<Addr> {
    Addr::parse(text)
}

fn config(enabled: bool, rate: f64, burst: i64, ipv4: i64, ipv6: i64, exempt: &[&str]) -> Config {
    Config {
        enabled,
        rate,
        burst,
        ipv4_prefix: ipv4,
        ipv6_prefix: ipv6,
        exempt: exempt.iter().map(|entry| entry.to_string()).collect(),
    }
}

const NOW: i64 = 1_700_000_000_000_000_000;

#[test]
fn zero_values_fall_back_to_the_documented_defaults() {
    let limiter = RateLimiter::new(&config(true, 0.0, 0, 0, 0, &[]));
    let info = limiter.info();
    assert_eq!(info.config.rate, DEFAULT_RATE);
    assert_eq!(info.config.burst, DEFAULT_BURST);
    assert_eq!(info.config.ipv4_prefix, 32);
    assert_eq!(info.config.ipv6_prefix, 128);

    limiter.configure(&config(true, 10.0, 5, 33, 129, &[]));
    let info = limiter.info();
    assert_eq!(info.config.rate, 10.0);
    assert_eq!(info.config.burst, 5);
    assert_eq!(info.config.ipv4_prefix, 32);
    assert_eq!(info.config.ipv6_prefix, 128);
}

#[test]
fn the_burst_is_spent_and_refilled_by_elapsed_time() {
    let limiter = RateLimiter::new(&config(true, 10.0, 5, 32, 128, &[]));
    let client = address("192.0.2.50");
    for index in 0..5 {
        assert!(
            limiter.allow(client.as_ref(), NOW, DEFAULT_MAX_BUCKETS),
            "request {} is inside the burst",
            index + 1
        );
    }
    assert!(!limiter.allow(client.as_ref(), NOW, DEFAULT_MAX_BUCKETS));
    assert_eq!(limiter.bucket_count(), 1);

    // 0.5s at 10/s is exactly five tokens.
    let later = NOW + 500_000_000;
    for _ in 0..5 {
        assert!(limiter.allow(client.as_ref(), later, DEFAULT_MAX_BUCKETS));
    }
    assert!(!limiter.allow(client.as_ref(), later, DEFAULT_MAX_BUCKETS));
}

#[test]
fn just_under_one_token_is_not_enough() {
    let limiter = RateLimiter::new(&config(true, 1.0, 2, 32, 128, &[]));
    let client = address("192.0.2.51");
    assert!(limiter.allow(client.as_ref(), NOW, DEFAULT_MAX_BUCKETS));
    assert!(limiter.allow(client.as_ref(), NOW, DEFAULT_MAX_BUCKETS));
    assert!(!limiter.allow(client.as_ref(), NOW + 999_999_999, DEFAULT_MAX_BUCKETS));
    assert!(limiter.allow(client.as_ref(), NOW + 1_000_000_001, DEFAULT_MAX_BUCKETS));
}

#[test]
fn a_disabled_limiter_allows_everything_and_creates_no_buckets() {
    let limiter = RateLimiter::new(&config(false, 1.0, 1, 32, 128, &[]));
    let client = address("192.0.2.52");
    for _ in 0..10 {
        assert!(limiter.allow(client.as_ref(), NOW, DEFAULT_MAX_BUCKETS));
    }
    assert_eq!(limiter.bucket_count(), 0);
    assert!(!limiter.enabled());

    // Enabling keeps whatever buckets already exist but starts counting again.
    limiter.configure(&config(true, 1.0, 1, 32, 128, &[]));
    assert!(limiter.allow(client.as_ref(), NOW, DEFAULT_MAX_BUCKETS));
    assert!(!limiter.allow(client.as_ref(), NOW, DEFAULT_MAX_BUCKETS));
    assert_eq!(limiter.bucket_count(), 1);
}

#[test]
fn exemptions_cover_literals_cidrs_and_the_mapped_form() {
    let limiter = RateLimiter::new(&config(
        true,
        1.0,
        1,
        32,
        128,
        &[
            " 127.0.0.1 ",
            "10.0.0.0/24",
            "::1",
            "2001:db8::/32",
            "::ffff:192.168.9.9",
            "garbage",
            "10.0.0.0/33",
            "01.2.3.4/8",
        ],
    ));
    for exempt in [
        "127.0.0.1",
        "10.0.0.42",
        "::1",
        "2001:db8::1",
        "192.168.9.9",
    ] {
        assert!(
            limiter.is_exempt(address(exempt).as_ref()),
            "{exempt} should be exempt"
        );
        assert!(limiter.allow(address(exempt).as_ref(), NOW, DEFAULT_MAX_BUCKETS));
    }
    for limited in ["127.0.0.2", "10.0.1.42", "::2", "2001:db9::1"] {
        assert!(
            !limiter.is_exempt(address(limited).as_ref()),
            "{limited} should not be exempt"
        );
    }
    assert!(limiter.is_exempt(None), "nil is exempt");
    assert_eq!(
        limiter.bucket_count(),
        0,
        "exempt clients never create buckets"
    );
    let info = limiter.info();
    assert_eq!(info.exempt_ips, 3);
    assert_eq!(info.exempt_nets, 2);
}

#[test]
fn the_mapped_cidr_corner_cases_stay_the_way_go_had_them() {
    let limiter = RateLimiter::new(&config(true, 1.0, 1, 32, 128, &["::ffff:10.0.0.0/120"]));
    assert!(limiter.is_exempt(address("10.0.0.7").as_ref()));
    assert!(!limiter.is_exempt(address("10.0.1.7").as_ref()));

    let limiter = RateLimiter::new(&config(true, 1.0, 1, 32, 128, &["::ffff:10.0.0.0/96"]));
    assert!(limiter.is_exempt(address("8.8.8.8").as_ref()));
    assert!(!limiter.is_exempt(address("2001:db8::1").as_ref()));
}

#[test]
fn prefixes_aggregate_clients_into_one_bucket() {
    let limiter = RateLimiter::new(&config(true, 1.0, 2, 24, 56, &[]));
    assert!(limiter.allow(address("192.168.1.10").as_ref(), NOW, DEFAULT_MAX_BUCKETS));
    assert!(limiter.allow(address("192.168.1.20").as_ref(), NOW, DEFAULT_MAX_BUCKETS));
    assert!(!limiter.allow(address("192.168.1.30").as_ref(), NOW, DEFAULT_MAX_BUCKETS));
    assert!(limiter.allow(address("192.168.2.10").as_ref(), NOW, DEFAULT_MAX_BUCKETS));
    assert_eq!(limiter.bucket_count(), 2);

    // A mapped client shares the IPv4 bucket.
    assert!(limiter.allow(
        address("::ffff:192.168.3.10").as_ref(),
        NOW,
        DEFAULT_MAX_BUCKETS
    ));
    assert!(limiter.allow(address("192.168.3.20").as_ref(), NOW, DEFAULT_MAX_BUCKETS));
    assert!(!limiter.allow(address("192.168.3.30").as_ref(), NOW, DEFAULT_MAX_BUCKETS));
}

#[test]
fn update_raises_capacity_by_the_delta_and_clamps_when_lowered() {
    let limiter = RateLimiter::new(&config(true, 0.000001, 5, 32, 128, &[]));
    let client = address("192.0.2.60");
    for _ in 0..5 {
        assert!(limiter.allow(client.as_ref(), NOW, DEFAULT_MAX_BUCKETS));
    }

    // +15 capacity shows up immediately: 15 tokens, five of them spent here.
    limiter.configure(&config(true, 0.000001, 20, 32, 128, &[]));
    let mut allowed = 0;
    for _ in 0..5 {
        if limiter.allow(client.as_ref(), NOW, DEFAULT_MAX_BUCKETS) {
            allowed += 1;
        }
    }
    assert_eq!(allowed, 5);

    // Lowering the burst clamps the stored 10 tokens down to 3.
    limiter.configure(&config(true, 0.000001, 3, 32, 128, &[]));
    let mut allowed = 0;
    for _ in 0..4 {
        if limiter.allow(client.as_ref(), NOW, DEFAULT_MAX_BUCKETS) {
            allowed += 1;
        }
    }
    assert_eq!(allowed, 3);
}

#[test]
fn the_oldest_bucket_is_evicted_at_capacity() {
    let limiter = RateLimiter::new(&config(true, 1.0, 2, 32, 128, &[]));
    let (first, second, third, fourth) = (
        address("10.0.0.1"),
        address("10.0.0.2"),
        address("10.0.0.3"),
        address("10.0.0.4"),
    );
    assert!(limiter.allow(first.as_ref(), NOW, 3));
    assert!(limiter.allow(second.as_ref(), NOW + 1_000_000_000, 3));
    assert!(limiter.allow(third.as_ref(), NOW + 2_000_000_000, 3));
    assert_eq!(limiter.bucket_count(), 3);

    // Evicts `first` (oldest last-refill), then `fourth` gets a full bucket.
    assert!(limiter.allow(fourth.as_ref(), NOW + 3_000_000_000, 3));
    assert_eq!(limiter.bucket_count(), 3);

    // `first` comes back as a brand-new bucket, evicting `second`.
    assert!(limiter.allow(first.as_ref(), NOW + 3_000_000_000, 3));
    assert_eq!(limiter.bucket_count(), 3);
    assert!(limiter.allow(first.as_ref(), NOW + 3_000_000_000, 3));
    assert!(!limiter.allow(first.as_ref(), NOW + 3_000_000_000, 3));
}

#[test]
fn zero_capacity_still_keeps_one_bucket() {
    let limiter = RateLimiter::new(&config(true, 1.0, 2, 32, 128, &[]));
    assert!(limiter.allow(address("10.0.0.1").as_ref(), NOW, 0));
    assert!(limiter.allow(address("10.0.0.2").as_ref(), NOW, 0));
    assert_eq!(limiter.bucket_count(), 1);
}

#[test]
fn the_idle_sweep_removes_nothing_because_a_used_bucket_is_never_full() {
    let limiter = RateLimiter::new(&config(true, 1.0, 1, 32, 128, &[]));
    assert!(limiter.allow(address("10.0.0.1").as_ref(), NOW, DEFAULT_MAX_BUCKETS));
    limiter.cleanup_idle(NOW + 61_000_000_000);
    assert_eq!(limiter.bucket_count(), 1, "isIdle requires tokens >= burst");
}

#[test]
fn a_backwards_clock_takes_tokens_away() {
    let limiter = RateLimiter::new(&config(true, 1.0, 5, 32, 128, &[]));
    let client = address("10.0.0.9");
    for _ in 0..5 {
        assert!(limiter.allow(client.as_ref(), NOW, DEFAULT_MAX_BUCKETS));
    }
    assert!(limiter.allow(client.as_ref(), NOW + 10_000_000_000, DEFAULT_MAX_BUCKETS));
    // 5s backwards: 4 remaining tokens minus 5 seconds of "refill" is negative.
    assert!(!limiter.allow(client.as_ref(), NOW + 5_000_000_000, DEFAULT_MAX_BUCKETS));
    assert!(!limiter.allow(client.as_ref(), NOW + 5_000_000_000, DEFAULT_MAX_BUCKETS));
}

#[test]
fn an_unknown_address_is_exempt_and_allowed() {
    let limiter = RateLimiter::new(&config(true, 1.0, 1, 32, 128, &[]));
    assert!(limiter.allow(None, NOW, DEFAULT_MAX_BUCKETS));
    assert_eq!(limiter.bucket_count(), 0);
}
