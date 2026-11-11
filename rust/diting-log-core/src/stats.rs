//! The notification's numbers: request counters buckets and the transfer rates derived from the
//! traffic ticks.
//!
//! `RequestStats` and `TrafficRateMonitor` were two process-wide singletons fed by the engine
//! callbacks; they now share one handle because every reader (the notification, the dashboard card)
//! takes both in the same breath. The classification lives here so the dashboard's "rewritten also
//! counts as passed" rule has exactly one implementation.

use std::sync::Mutex;

use crate::row::{is_blank, DnsInput};

/// A late or post-idle tick is divided by at most this interval, so a burst is not turned into a
/// fraction by the whole idle gap (the engine only ticks when it has data, so gaps can be seconds).
const MAX_RATE_INTERVAL_MS: i64 = 2_000;
/// No data tick for this long means the link is idle: report zero instead of the last value.
const RATE_STALE_MS: i64 = 3_000;

/// `RequestStats.Snapshot`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct RequestSnapshot {
    pub total: i64,
    pub passed: i64,
    pub filtered: i64,
    pub cached: i64,
    pub rewritten: i64,
    pub failed: i64,
}

#[derive(Debug, Default)]
struct Inner {
    requests: RequestSnapshot,
    last_tx: i64,
    last_rx: i64,
    last_at_ms: i64,
    tx_bps: i64,
    rx_bps: i64,
}

/// The request counters plus the rate monitor.
#[derive(Debug, Default)]
pub struct Stats {
    inner: Mutex<Inner>,
}

impl Stats {
    pub fn new() -> Self {
        Self::default()
    }

    /// `RequestStats.onDns`: one entry of the engine's batch DNS log.
    ///
    /// Connection and firewall lines are flows, not queries, so they stay out like they do on the
    /// dashboard's request overview; a blank domain is not a query either.
    pub fn record_dns(&self, input: &DnsInput) {
        if is_blank(&input.domain) {
            return;
        }
        if input.query_type == 0
            || input.blocked_by == "connection"
            || input.blocked_by.starts_with("firewall:")
        {
            return;
        }
        let mut inner = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        inner.requests.total += 1;
        if !is_blank(&input.error) {
            inner.requests.failed += 1;
            return;
        }
        if input.blocked_by.starts_with("rewrite=") {
            inner.requests.rewritten += 1;
            inner.requests.passed += 1;
            return;
        }
        if input.blocked {
            inner.requests.filtered += 1;
            return;
        }
        inner.requests.passed += 1;
        if input.cached {
            inner.requests.cached += 1;
        }
    }

    /// `RequestStats.onHttp`: the HTTPS outcome, mapped like `httpRowStatusOf` on the Dart side.
    pub fn record_http(&self, outcome: &str) {
        let mut inner = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        inner.requests.total += 1;
        match outcome {
            "allowed" => inner.requests.passed += 1,
            "rewritten" => {
                inner.requests.rewritten += 1;
                inner.requests.passed += 1;
            }
            "blocked" | "invalid" => inner.requests.filtered += 1,
            // Bypassed flows count toward the total only.
            "passthrough" | "bypassed" | "unsupported_protocol" | "resource_bypass" => {}
            _ => inner.requests.failed += 1,
        }
    }

    pub fn request_snapshot(&self) -> RequestSnapshot {
        self.inner
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .requests
    }

    pub fn reset_requests(&self) {
        let mut inner = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        inner.requests = RequestSnapshot::default();
    }

    /// `TrafficRateMonitor.onTick`: per-second rates from the tick delta.
    ///
    /// The first tick only stamps the clock (there is no interval to divide by yet), and a
    /// non-positive interval is ignored rather than divided by zero. The interval is clamped to
    /// [`MAX_RATE_INTERVAL_MS`] so the first tick after an idle gap is not divided by the gap.
    pub fn tick_rate(&self, tx: i64, rx: i64, now_ms: i64) {
        let mut inner = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        let previous = inner.last_at_ms;
        if previous > 0 {
            let elapsed = now_ms.wrapping_sub(previous);
            if elapsed <= 0 {
                return;
            }
            // Divide by the interval this delta covers, but never by the whole idle gap.
            let interval = elapsed.min(MAX_RATE_INTERVAL_MS);
            inner.tx_bps = tx.wrapping_mul(1000) / interval;
            inner.rx_bps = rx.wrapping_mul(1000) / interval;
            inner.last_tx = tx;
            inner.last_rx = rx;
        }
        inner.last_at_ms = now_ms;
    }

    /// The rates for `now_ms`. A link that has not ticked for [`RATE_STALE_MS`] is idle, so the last
    /// value must not be reported forever.
    pub fn rate_snapshot(&self, now_ms: i64) -> (i64, i64) {
        let inner = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        if inner.last_at_ms == 0 || now_ms.wrapping_sub(inner.last_at_ms) > RATE_STALE_MS {
            return (0, 0);
        }
        (inner.tx_bps, inner.rx_bps)
    }

    pub fn reset_rate(&self) {
        let mut inner = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        inner.last_tx = 0;
        inner.last_rx = 0;
        inner.last_at_ms = 0;
        inner.tx_bps = 0;
        inner.rx_bps = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dns(domain: &str) -> DnsInput {
        DnsInput {
            domain: domain.to_string(),
            query_type: 1,
            ..DnsInput::default()
        }
    }

    #[test]
    fn dns_buckets_follow_the_dashboard_rules() {
        let stats = Stats::new();
        stats.record_dns(&dns("example.com"));
        let snapshot = stats.request_snapshot();
        assert_eq!(
            (snapshot.total, snapshot.passed, snapshot.cached),
            (1, 1, 0)
        );

        let cached = DnsInput {
            cached: true,
            ..dns("example.com")
        };
        stats.record_dns(&cached);
        let snapshot = stats.request_snapshot();
        // A cached answer counts as passed *and* cached.
        assert_eq!(
            (snapshot.total, snapshot.passed, snapshot.cached),
            (2, 2, 1)
        );

        let blocked = DnsInput {
            blocked: true,
            ..dns("ads.example")
        };
        stats.record_dns(&blocked);
        assert_eq!(stats.request_snapshot().filtered, 1);

        let rewritten = DnsInput {
            blocked_by: "rewrite=1.2.3.4".into(),
            ..dns("example.com")
        };
        stats.record_dns(&rewritten);
        let snapshot = stats.request_snapshot();
        assert_eq!((snapshot.rewritten, snapshot.passed), (1, 3));

        let failed = DnsInput {
            error: "timeout".into(),
            ..dns("example.com")
        };
        stats.record_dns(&failed);
        assert_eq!(stats.request_snapshot().failed, 1);
    }

    #[test]
    fn flows_and_blank_domains_are_not_queries() {
        let stats = Stats::new();
        let connection = DnsInput {
            blocked_by: "connection".into(),
            ..dns("example.com")
        };
        stats.record_dns(&connection);
        let firewall = DnsInput {
            blocked_by: "firewall:3".into(),
            ..dns("example.com")
        };
        stats.record_dns(&firewall);
        let no_type = DnsInput {
            query_type: 0,
            ..dns("example.com")
        };
        stats.record_dns(&no_type);
        stats.record_dns(&dns("  "));
        assert_eq!(stats.request_snapshot().total, 0);
    }

    #[test]
    fn http_outcomes_map_like_the_dart_statuses() {
        let stats = Stats::new();
        for outcome in ["allowed", "rewritten", "blocked", "invalid"] {
            stats.record_http(outcome);
        }
        for outcome in [
            "passthrough",
            "bypassed",
            "unsupported_protocol",
            "resource_bypass",
        ] {
            stats.record_http(outcome);
        }
        stats.record_http("error");
        stats.record_http("");
        let snapshot = stats.request_snapshot();
        assert_eq!(snapshot.total, 10);
        assert_eq!(snapshot.passed, 2);
        assert_eq!(snapshot.rewritten, 1);
        assert_eq!(snapshot.filtered, 2);
        assert_eq!(snapshot.failed, 2);
        assert_eq!(snapshot.cached, 0);
    }

    #[test]
    fn rates_need_two_ticks_and_a_positive_interval() {
        let stats = Stats::new();
        stats.tick_rate(1000, 2000, 10_000);
        // The first tick only stamps the clock.
        assert_eq!(stats.rate_snapshot(10_000), (0, 0));

        stats.tick_rate(3000, 5000, 11_000);
        assert_eq!(stats.rate_snapshot(11_000), (3000, 5000));

        // A late callback divides by the real interval, here two seconds.
        stats.tick_rate(6000, 10_000, 13_000);
        assert_eq!(stats.rate_snapshot(13_000), (3000, 5000));

        // A clock that did not move (or went back) leaves the rates alone.
        stats.tick_rate(9000, 15_000, 13_000);
        assert_eq!(stats.rate_snapshot(13_000), (3000, 5000));

        stats.reset_rate();
        assert_eq!(stats.rate_snapshot(13_000), (0, 0));
    }

    #[test]
    fn a_stale_snapshot_reads_zero_and_idle_ticks_decay() {
        let stats = Stats::new();
        stats.tick_rate(100_000, 200_000, 10_000);
        stats.tick_rate(100_000, 200_000, 11_000);
        assert_eq!(stats.rate_snapshot(11_000), (100_000, 200_000));

        // No tick for more than RATE_STALE_MS: the link is idle, so do not keep the old value.
        assert_eq!(stats.rate_snapshot(15_000), (0, 0));

        // The empty-tick path feeds (0, 0) every second, which also drives the rate to zero.
        stats.tick_rate(0, 0, 12_000);
        assert_eq!(stats.rate_snapshot(12_000), (0, 0));
    }

    #[test]
    fn a_post_idle_tick_is_not_divided_by_the_whole_gap() {
        let stats = Stats::new();
        stats.tick_rate(1, 1, 1_000);
        // 60 s of silence, then 100 KB in one burst: clamp to 2 s, not 60 s.
        stats.tick_rate(100_000, 100_000, 61_000);
        assert_eq!(stats.rate_snapshot(61_000), (50_000, 50_000));
    }

    #[test]
    fn resetting_requests_keeps_the_rates() {
        let stats = Stats::new();
        stats.record_http("allowed");
        stats.tick_rate(1, 1, 1);
        stats.tick_rate(10, 10, 2);
        stats.reset_requests();
        assert_eq!(stats.request_snapshot(), RequestSnapshot::default());
        assert_eq!(stats.rate_snapshot(2), (10_000, 10_000));
    }
}
