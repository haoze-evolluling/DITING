//! Client rate limiting.
//!
//! Thin facade over `diting-ratelimit-core`, mirroring `rate_limiter.go`. The
//! kernel owns the token buckets, prefix aggregation, exemption parsing, the
//! capacity eviction and the idle sweep; this module supplies a monotonic clock
//! in nanoseconds, the bucket cap and the configuration mapping. The clock is
//! anchored at construction so wall-clock changes can never refill or drain a
//! bucket retroactively.

use std::net::IpAddr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};
use std::time::Instant;

use diting_desktop_api::config::RateLimitConfig;
use diting_ratelimit_core::{Addr, Config, Info};

/// Bucket capacity. The Go limiter carried the same value per call; the kernel
/// exposes it as `DEFAULT_MAX_BUCKETS`.
pub const MAX_BUCKETS: u32 = diting_ratelimit_core::DEFAULT_MAX_BUCKETS;

/// Idle buckets are swept every this many `allow` calls instead of running a
/// dedicated janitor task.
const CLEANUP_EVERY: u64 = 1024;

struct State {
    kernel: diting_ratelimit_core::RateLimiter,
    config: RateLimitConfig,
}

/// Thread-safe client rate limiter.
pub struct RateLimiter {
    state: RwLock<State>,
    started: Instant,
    calls: AtomicU64,
}

impl RateLimiter {
    pub fn new(config: &RateLimitConfig) -> Self {
        Self {
            state: RwLock::new(State {
                kernel: diting_ratelimit_core::RateLimiter::new(&kernel_config(config)),
                config: config.clone(),
            }),
            started: Instant::now(),
            calls: AtomicU64::new(0),
        }
    }

    /// Replaces the configuration. The kernel keeps live buckets and adjusts
    /// their capacity to the new burst, exactly like `UpdateConfig`.
    pub fn configure(&self, config: &RateLimitConfig) {
        let mut state = self.write();
        state.kernel.configure(&kernel_config(config));
        state.config = config.clone();
    }

    pub fn enabled(&self) -> bool {
        self.read().kernel.enabled()
    }

    /// Admits or rejects one request. A missing address and a disabled limiter
    /// both pass, matching the Go middleware's fast path.
    pub fn allow(&self, ip: Option<IpAddr>) -> bool {
        let now = self.now_ns();
        let address = ip.map(addr_for);

        let allowed = {
            let state = self.read();
            state.kernel.allow(address.as_ref(), now, MAX_BUCKETS)
        };

        let calls = self.calls.fetch_add(1, Ordering::Relaxed).wrapping_add(1);
        if calls.is_multiple_of(CLEANUP_EVERY) {
            self.read().kernel.cleanup_idle(now);
        }
        allowed
    }

    /// Whether an address bypasses the limiter. A missing address counts as
    /// exempt, like Go's `IsExempt(nil)`.
    pub fn is_exempt(&self, ip: Option<IpAddr>) -> bool {
        let address = ip.map(addr_for);
        self.read().kernel.is_exempt(address.as_ref())
    }

    /// The configuration this limiter was last given.
    pub fn config(&self) -> RateLimitConfig {
        self.read().config.clone()
    }

    pub fn info(&self) -> Info {
        self.read().kernel.info()
    }

    fn now_ns(&self) -> i64 {
        i64::try_from(self.started.elapsed().as_nanos()).unwrap_or(i64::MAX)
    }

    fn read(&self) -> RwLockReadGuard<'_, State> {
        self.state
            .read()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn write(&self) -> RwLockWriteGuard<'_, State> {
        self.state
            .write()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

fn kernel_config(config: &RateLimitConfig) -> Config {
    Config {
        enabled: config.enabled,
        rate: config.rate,
        burst: i64::from(config.burst),
        ipv4_prefix: i64::from(config.ipv4_prefix),
        ipv6_prefix: i64::from(config.ipv6_prefix),
        exempt: config.exempt_ips.clone(),
    }
}

fn addr_for(ip: IpAddr) -> Addr {
    match ip {
        IpAddr::V4(v4) => Addr::from_bytes(&v4.octets()).unwrap_or(Addr::V4(v4.octets())),
        IpAddr::V6(v6) => Addr::from_bytes(&v6.octets()).unwrap_or(Addr::V6(v6.octets())),
    }
}

#[cfg(test)]
mod tests;
