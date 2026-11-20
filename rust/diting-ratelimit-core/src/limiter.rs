use std::collections::{HashMap, HashSet};
use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};

use crate::cidr::Cidr;
use crate::ip::Addr;

pub const DEFAULT_RATE: f64 = 50.0;
pub const DEFAULT_BURST: i64 = 100;
pub const DEFAULT_IPV4_PREFIX: i64 = 32;
pub const DEFAULT_IPV6_PREFIX: i64 = 128;
pub const DEFAULT_MAX_BUCKETS: u32 = 16384;
pub const IDLE_AFTER_NS: i128 = 60_000_000_000;

#[derive(Clone, Debug, Default)]
pub struct Config {
    pub enabled: bool,
    pub rate: f64,
    pub burst: i64,
    pub ipv4_prefix: i64,
    pub ipv6_prefix: i64,
    pub exempt: Vec<String>,
}

impl Config {
    pub fn normalized(&self) -> Normalized {
        Normalized {
            enabled: self.enabled,
            rate: if self.rate <= 0.0 {
                DEFAULT_RATE
            } else {
                self.rate
            },
            burst: if self.burst <= 0 {
                DEFAULT_BURST
            } else {
                self.burst
            },
            ipv4_prefix: prefix_or_default(self.ipv4_prefix, 32),
            ipv6_prefix: prefix_or_default(self.ipv6_prefix, 128),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Normalized {
    pub enabled: bool,
    pub rate: f64,
    pub burst: i64,
    pub ipv4_prefix: u8,
    pub ipv6_prefix: u8,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Info {
    pub config: Normalized,
    pub buckets: u32,
    pub exempt_ips: u32,
    pub exempt_nets: u32,
}

struct Bucket {
    rate: f64,
    burst: f64,
    tokens: f64,
    last_refill_ns: i128,
}

impl Bucket {
    fn new(rate: f64, burst: f64, now_ns: i128) -> Self {
        Bucket {
            rate,
            burst,
            tokens: burst,
            last_refill_ns: now_ns,
        }
    }

    fn allow(&mut self, now_ns: i128) -> bool {
        let elapsed = (now_ns - self.last_refill_ns) as f64 / 1e9;
        self.last_refill_ns = now_ns;
        self.tokens += elapsed * self.rate;
        if self.tokens > self.burst {
            self.tokens = self.burst;
        }
        if self.tokens >= 1.0 {
            self.tokens -= 1.0;
            return true;
        }
        false
    }

    fn is_idle(&self, now_ns: i128) -> bool {
        self.tokens >= self.burst && (now_ns - self.last_refill_ns) > IDLE_AFTER_NS
    }
}

struct State {
    config: Normalized,
    exempt_ips: HashSet<Addr>,
    exempt_nets: Vec<Cidr>,
    buckets: HashMap<Addr, Bucket>,
}

impl State {
    fn is_exempt(&self, address: &Addr) -> bool {
        self.exempt_ips.contains(address)
            || self
                .exempt_nets
                .iter()
                .any(|network| network.contains(address))
    }

    fn bucket_key(&self, address: &Addr) -> Addr {
        match address {
            Addr::V4(_) => address.masked(self.config.ipv4_prefix),
            Addr::V6(_) => address.masked(self.config.ipv6_prefix),
        }
    }

    fn parse_exemptions(&mut self, entries: &[String]) {
        for entry in entries {
            let entry = entry.trim();
            if entry.is_empty() {
                continue;
            }
            if entry.contains('/') {
                if let Some(network) = Cidr::parse(entry) {
                    self.exempt_nets.push(network);
                }
            } else if let Some(address) = Addr::parse(entry) {
                self.exempt_ips.insert(address);
            }
        }
    }
}

pub struct RateLimiter {
    state: RwLock<State>,
}

impl RateLimiter {
    pub fn new(config: &Config) -> Self {
        let normalized = config.normalized();
        let mut state = State {
            config: normalized,
            exempt_ips: HashSet::new(),
            exempt_nets: Vec::new(),
            buckets: HashMap::new(),
        };
        state.parse_exemptions(&config.exempt);
        Self {
            state: RwLock::new(state),
        }
    }

    pub fn configure(&self, config: &Config) {
        let normalized = config.normalized();
        let mut state = self.write();
        state.config = normalized;
        state.exempt_ips.clear();
        state.exempt_nets.clear();
        state.parse_exemptions(&config.exempt);

        for bucket in state.buckets.values_mut() {
            let old_burst = bucket.burst;
            bucket.rate = normalized.rate;
            bucket.burst = normalized.burst as f64;
            if bucket.burst > old_burst {
                bucket.tokens += bucket.burst - old_burst;
            }
            if bucket.tokens > bucket.burst {
                bucket.tokens = bucket.burst;
            }
        }
    }

    pub fn enabled(&self) -> bool {
        self.read().config.enabled
    }

    pub fn is_exempt(&self, address: Option<&Addr>) -> bool {
        let Some(address) = address else {
            return true;
        };
        self.read().is_exempt(address)
    }

    pub fn allow(&self, address: Option<&Addr>, now_ns: i64, max_buckets: u32) -> bool {
        let mut state = self.write();
        if !state.config.enabled {
            return true;
        }
        let Some(address) = address else {
            return true;
        };
        if state.is_exempt(address) {
            return true;
        }

        let key = state.bucket_key(address);
        let now_ns = i128::from(now_ns);
        if !state.buckets.contains_key(&key) {
            if state.buckets.len() >= max_buckets as usize {
                state.buckets.retain(|_, bucket| !bucket.is_idle(now_ns));
                if state.buckets.len() >= max_buckets as usize {
                    let oldest = state
                        .buckets
                        .iter()
                        .min_by_key(|(_, bucket)| bucket.last_refill_ns)
                        .map(|(key, _)| *key);
                    if let Some(oldest) = oldest {
                        state.buckets.remove(&oldest);
                    }
                }
            }
            let bucket = Bucket::new(state.config.rate, state.config.burst as f64, now_ns);
            state.buckets.insert(key, bucket);
        }

        state
            .buckets
            .get_mut(&key)
            .expect("the bucket was just inserted")
            .allow(now_ns)
    }

    pub fn cleanup_idle(&self, now_ns: i64) {
        let now_ns = i128::from(now_ns);
        self.write()
            .buckets
            .retain(|_, bucket| !bucket.is_idle(now_ns));
    }

    pub fn info(&self) -> Info {
        let state = self.read();
        Info {
            config: state.config,
            buckets: state.buckets.len() as u32,
            exempt_ips: state.exempt_ips.len() as u32,
            exempt_nets: state.exempt_nets.len() as u32,
        }
    }

    pub fn bucket_count(&self) -> u32 {
        self.read().buckets.len() as u32
    }

    fn read(&self) -> RwLockReadGuard<'_, State> {
        self.state.read().unwrap_or_else(|error| error.into_inner())
    }

    fn write(&self) -> RwLockWriteGuard<'_, State> {
        self.state
            .write()
            .unwrap_or_else(|error| error.into_inner())
    }
}

fn prefix_or_default(value: i64, maximum: i64) -> u8 {
    if value <= 0 || value > maximum {
        maximum as u8
    } else {
        value as u8
    }
}

#[cfg(test)]
mod tests;
