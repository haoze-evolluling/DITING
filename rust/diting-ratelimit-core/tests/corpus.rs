//! Replays the trace produced by the Go `RateLimiter` before this crate replaced it
//! (`internal/core/zz_ratelimit_fixture_gen_test.go`, deleted with the Go implementation).
//!
//! Each row is `op | arg1..arg6 | expect`. The script covers the default normalisation, the token
//! bucket (burst / refill / clamping / a backwards clock), IPv4 and IPv6 prefix aggregation,
//! exemption parsing (literals, CIDRs, mapped forms, whitespace, invalid entries), the v4-mapped
//! CIDR corner cases, capacity eviction, the dead idle sweep, and burst changes on update.

use diting_ratelimit_core::{Addr, Config, Info, RateLimiter, DEFAULT_MAX_BUCKETS};

const TRACE: &str = include_str!("fixtures/ratelimit_trace.tsv");

struct Harness {
    limiter: Option<RateLimiter>,
    now_ns: i64,
    max_buckets: u32,
}

impl Harness {
    fn new() -> Self {
        Harness {
            limiter: None,
            now_ns: 0,
            max_buckets: DEFAULT_MAX_BUCKETS,
        }
    }

    fn limiter(&self) -> &RateLimiter {
        self.limiter.as_ref().expect("a `new` row must come first")
    }
}

fn config(args: &[&str]) -> Config {
    Config {
        enabled: args[0] == "1",
        rate: args[1].parse().expect("rate"),
        burst: args[2].parse().expect("burst"),
        ipv4_prefix: args[3].parse().expect("ipv4 prefix"),
        ipv6_prefix: args[4].parse().expect("ipv6 prefix"),
        exempt: if args[5].is_empty() {
            Vec::new()
        } else {
            args[5].split(';').map(|entry| entry.to_string()).collect()
        },
    }
}

fn check_info(info: Info, expect: &str, row: &str) {
    let fields: Vec<&str> = expect.split('|').collect();
    assert_eq!(fields.len(), 8, "info fields: {row}");
    let enabled = if info.config.enabled { "1" } else { "0" };
    assert_eq!(fields[0], enabled, "enabled: {row}");
    let rate: f64 = fields[1].parse().expect("rate");
    assert_eq!(rate.to_bits(), info.config.rate.to_bits(), "rate: {row}");
    assert_eq!(
        fields[2].parse::<i64>().unwrap(),
        info.config.burst,
        "burst: {row}"
    );
    assert_eq!(
        fields[3].parse::<u8>().unwrap(),
        info.config.ipv4_prefix,
        "ipv4 prefix: {row}"
    );
    assert_eq!(
        fields[4].parse::<u8>().unwrap(),
        info.config.ipv6_prefix,
        "ipv6 prefix: {row}"
    );
    assert_eq!(
        fields[5].parse::<u32>().unwrap(),
        info.buckets,
        "buckets: {row}"
    );
    assert_eq!(
        fields[6].parse::<u32>().unwrap(),
        info.exempt_ips,
        "exempt IPs: {row}"
    );
    assert_eq!(
        fields[7].parse::<u32>().unwrap(),
        info.exempt_nets,
        "exempt nets: {row}"
    );
}

#[test]
fn the_trace_replays_exactly() {
    let mut harness = Harness::new();
    let mut rows = 0usize;

    for line in TRACE.lines() {
        if line.is_empty() || line.starts_with('#') || line.starts_with("op\t") {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        assert_eq!(fields.len(), 8, "row shape: {line}");
        let (op, args, expect) = (fields[0], &fields[1..7], fields[7]);
        match op {
            "new" => {
                harness.limiter = None;
                harness.limiter = Some(RateLimiter::new(&config(args)));
                check_info(harness.limiter().info(), expect, line);
            }
            "update" => {
                harness.limiter().configure(&config(args));
                check_info(harness.limiter().info(), expect, line);
            }
            "now" => {
                harness.now_ns = args[0].parse().expect("now");
            }
            "max" => {
                harness.max_buckets = args[0].parse().expect("max buckets");
            }
            "allow" => {
                let address = Addr::parse(args[0]);
                let allowed =
                    harness
                        .limiter()
                        .allow(address.as_ref(), harness.now_ns, harness.max_buckets);
                let (want_allowed, want_buckets) = expect.split_once('|').expect("allowed|buckets");
                assert_eq!(
                    if allowed { "1" } else { "0" },
                    want_allowed,
                    "decision: {line}"
                );
                assert_eq!(
                    harness.limiter().bucket_count(),
                    want_buckets.parse::<u32>().expect("buckets"),
                    "buckets: {line}"
                );
            }
            "exempt" => {
                let address = Addr::parse(args[0]);
                let exempt = harness.limiter().is_exempt(address.as_ref());
                assert_eq!(if exempt { "1" } else { "0" }, expect, "exempt: {line}");
            }
            "cleanup" => {
                harness.limiter().cleanup_idle(harness.now_ns);
                assert_eq!(
                    harness.limiter().bucket_count(),
                    expect.parse::<u32>().expect("buckets"),
                    "cleanup buckets: {line}"
                );
            }
            "enabled" => {
                assert_eq!(
                    if harness.limiter().enabled() {
                        "1"
                    } else {
                        "0"
                    },
                    expect,
                    "enabled: {line}"
                );
            }
            other => panic!("unknown op {other:?}: {line}"),
        }
        rows += 1;
    }

    assert_eq!(rows, 156, "the fixture is the generated 156-step trace");
}
