//! Per-UID connection rate limiting for the normal tunnel data plane.
//!
//! One limiter keeps two token buckets per app UID: DNS queries and newly opened connections.
//! Both buckets share the configured rate and burst. The table is bounded and drops idle entries
//! when it reaches capacity, so a long-running tunnel cannot grow it without limit.

use std::collections::HashMap;
use std::sync::{Mutex, MutexGuard};

/// Defaults and bounds, mirrored by the Flutter page.
pub const DEFAULT_RATE: i64 = 50;
pub const DEFAULT_BURST: i64 = 100;
pub const MIN_RATE: i64 = 5;
pub const MAX_RATE: i64 = 1000;
pub const MIN_BURST: i64 = 10;
pub const MAX_BURST: i64 = 2000;
pub const MAX_UIDS: usize = 4096;
pub const IDLE_AFTER_NS: i64 = 60_000_000_000;

/// The limiter configuration as the DNS document carries it.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Config {
    pub enabled: bool,
    pub rate: i64,
    pub burst: i64,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            enabled: false,
            rate: DEFAULT_RATE,
            burst: DEFAULT_BURST,
        }
    }
}

impl Config {
    /// Keeps absent or out-of-range values inside the same bounds the page enforces.
    pub fn normalized(self) -> Self {
        Self {
            enabled: self.enabled,
            rate: if self.rate <= 0 {
                DEFAULT_RATE
            } else {
                self.rate.clamp(MIN_RATE, MAX_RATE)
            },
            burst: if self.burst <= 0 {
                DEFAULT_BURST
            } else {
                self.burst.clamp(MIN_BURST, MAX_BURST)
            },
        }
    }
}

/// Which bucket a packet or flow consumes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BucketKind {
    Query,
    Connection,
}

struct Bucket {
    tokens: f64,
    last_refill_ns: i64,
}

impl Bucket {
    fn new(burst: i64, now_ns: i64) -> Self {
        Self {
            tokens: burst as f64,
            last_refill_ns: now_ns,
        }
    }

    fn allow(&mut self, rate: i64, burst: i64, now_ns: i64) -> bool {
        let elapsed = now_ns.saturating_sub(self.last_refill_ns).max(0) as f64 / 1e9;
        self.last_refill_ns = now_ns;
        self.tokens = (self.tokens + elapsed * rate as f64).min(burst as f64);
        if self.tokens >= 1.0 {
            self.tokens -= 1.0;
            true
        } else {
            false
        }
    }
}

struct UidBuckets {
    query: Bucket,
    connection: Bucket,
    last_seen_ns: i64,
}

struct State {
    config: Config,
    buckets: HashMap<i32, UidBuckets>,
}

/// One published limiter. Replacing the config publishes a fresh limiter, so a hot apply also
/// starts every UID with a full burst, which is the least surprising behaviour after a rate change.
pub struct ConnectionLimiter {
    state: Mutex<State>,
}

impl ConnectionLimiter {
    pub fn new(config: Config) -> Self {
        Self {
            state: Mutex::new(State {
                config: config.normalized(),
                buckets: HashMap::new(),
            }),
        }
    }

    /// Returns whether this UID may spend a token from `kind` at `now_ns`.
    pub fn allow(&self, kind: BucketKind, uid: i32, now_ns: i64) -> bool {
        let mut state = self.state();
        if !state.config.enabled {
            return true;
        }
        if !state.buckets.contains_key(&uid) {
            state.cleanup_idle(now_ns);
            if state.buckets.len() >= MAX_UIDS {
                state.evict_oldest();
            }
            let burst = state.config.burst;
            state.buckets.insert(
                uid,
                UidBuckets {
                    query: Bucket::new(burst, now_ns),
                    connection: Bucket::new(burst, now_ns),
                    last_seen_ns: now_ns,
                },
            );
        }
        let config = state.config;
        let bucket = state.buckets.get_mut(&uid).expect("inserted above");
        bucket.last_seen_ns = now_ns;
        match kind {
            BucketKind::Query => bucket.query.allow(config.rate, config.burst, now_ns),
            BucketKind::Connection => bucket.connection.allow(config.rate, config.burst, now_ns),
        }
    }

    /// Drops UIDs that have been idle for a minute.
    pub fn cleanup_idle(&self, now_ns: i64) {
        self.state().cleanup_idle(now_ns);
    }

    /// Number of live UID entries, for diagnostics and tests.
    pub fn uid_count(&self) -> usize {
        self.state().buckets.len()
    }

    fn state(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|error| error.into_inner())
    }
}

impl State {
    fn cleanup_idle(&mut self, now_ns: i64) {
        self.buckets
            .retain(|_, bucket| now_ns.saturating_sub(bucket.last_seen_ns) <= IDLE_AFTER_NS);
    }

    fn evict_oldest(&mut self) {
        let oldest = self
            .buckets
            .iter()
            .min_by_key(|(_, bucket)| bucket.last_seen_ns)
            .map(|(uid, _)| *uid);
        if let Some(uid) = oldest {
            self.buckets.remove(&uid);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn enabled(rate: i64, burst: i64) -> ConnectionLimiter {
        ConnectionLimiter::new(Config {
            enabled: true,
            rate,
            burst,
        })
    }

    #[test]
    fn disabled_config_allows_everything() {
        let limiter = ConnectionLimiter::new(Config::default());
        for _ in 0..10_000 {
            assert!(limiter.allow(BucketKind::Query, 1000, 0));
        }
    }

    #[test]
    fn burst_is_consumed_then_refilled() {
        let limiter = enabled(10, 10);
        for _ in 0..10 {
            assert!(limiter.allow(BucketKind::Query, 1000, 0));
        }
        assert!(!limiter.allow(BucketKind::Query, 1000, 0));
        assert!(limiter.allow(BucketKind::Query, 1000, 100_000_000));
        assert!(!limiter.allow(BucketKind::Query, 1000, 100_000_000));
    }

    #[test]
    fn query_and_connection_buckets_are_independent() {
        let limiter = enabled(1, 10);
        for _ in 0..10 {
            assert!(limiter.allow(BucketKind::Query, 1000, 0));
        }
        assert!(!limiter.allow(BucketKind::Query, 1000, 0));
        assert!(limiter.allow(BucketKind::Connection, 1000, 0));
    }

    #[test]
    fn uids_do_not_share_buckets() {
        let limiter = enabled(1, 10);
        for _ in 0..10 {
            assert!(limiter.allow(BucketKind::Query, 1000, 0));
        }
        assert!(!limiter.allow(BucketKind::Query, 1000, 0));
        assert!(limiter.allow(BucketKind::Query, 1001, 0));
    }

    #[test]
    fn idle_entries_are_reclaimed_and_the_table_is_bounded() {
        let limiter = enabled(1, 10);
        for uid in 0..MAX_UIDS as i32 {
            assert!(limiter.allow(BucketKind::Query, uid, 0));
        }
        assert_eq!(limiter.uid_count(), MAX_UIDS);
        assert!(limiter.allow(BucketKind::Query, 99_999, 0));
        assert_eq!(limiter.uid_count(), MAX_UIDS);

        limiter.cleanup_idle(IDLE_AFTER_NS + 1);
        assert_eq!(limiter.uid_count(), 0);
    }
}
