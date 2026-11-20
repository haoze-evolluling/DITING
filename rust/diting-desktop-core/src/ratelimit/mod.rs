use std::net::IpAddr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};
use std::time::Instant;

use diting_desktop_api::config::RateLimitConfig;
use diting_ratelimit_core::{Addr, Config, Info};

pub const MAX_BUCKETS: u32 = diting_ratelimit_core::DEFAULT_MAX_BUCKETS;

const CLEANUP_EVERY: u64 = 1024;

struct State {
    kernel: diting_ratelimit_core::RateLimiter,
    config: RateLimitConfig,
}

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

    pub fn configure(&self, config: &RateLimitConfig) {
        let mut state = self.write();
        state.kernel.configure(&kernel_config(config));
        state.config = config.clone();
    }

    pub fn enabled(&self) -> bool {
        self.read().kernel.enabled()
    }

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

    pub fn is_exempt(&self, ip: Option<IpAddr>) -> bool {
        let address = ip.map(addr_for);
        self.read().kernel.is_exempt(address.as_ref())
    }

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
