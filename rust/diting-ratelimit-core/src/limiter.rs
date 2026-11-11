//! The limiter: configuration normalisation, exemptions, token buckets and the allow decision.
//!
//! Everything the Go implementation decided is decided here:
//!
//! * `NewRateLimiter`/`UpdateConfig` normalisation — `Rate <= 0` becomes 50, `Burst <= 0` becomes
//!   100, an out-of-range prefix becomes 32 or 128;
//! * exemption parsing — `strings.TrimSpace`, then a `/` means `ParseCIDR`, otherwise `ParseIP`
//!   with the `To4` collapse; unparseable entries are ignored;
//! * `UpdateConfig` keeps the existing buckets and raises their capacity by the burst delta
//!   (`tokens += newBurst - oldBurst`, then clamp), exactly like the Go loop over `r.buckets`;
//! * `Allow` — the enabled check, the exemption check, prefix aggregation into a bucket key, the
//!   capacity eviction, then the token bucket;
//! * the idle sweep and `is_idle`'s exact condition.
//!
//! One deliberate simplification: Go took the global write lock for the map lookup and released it
//! before the per-bucket mutex, ours holds one lock for the whole decision. The extra serialisation
//! is a handful of float operations; the observable decisions are identical.
//!
//! `is_idle` is unreachable in practice on both sides: a bucket is always left with `burst - 1`
//! tokens (or fewer) after an `allow`, so `tokens >= burst` never holds. The condition is kept
//! anyway — "空闲桶回收" is part of the module's documented behaviour, and the corpus records that
//! it removes nothing.

use std::collections::{HashMap, HashSet};
use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};

use crate::cidr::Cidr;
use crate::ip::Addr;

/// `RateLimitConfig` default rate when the configured one is not positive.
pub const DEFAULT_RATE: f64 = 50.0;
/// Default burst when the configured one is not positive.
pub const DEFAULT_BURST: i64 = 100;
/// Default IPv4 aggregation prefix.
pub const DEFAULT_IPV4_PREFIX: i64 = 32;
/// Default IPv6 aggregation prefix.
pub const DEFAULT_IPV6_PREFIX: i64 = 128;
/// The Go limiter field's default. The kernel takes it per call, so this is only a convenience for
/// tests that need the production value.
pub const DEFAULT_MAX_BUCKETS: u32 = 16384;
/// `isIdle`'s threshold: more than one minute since the last refill.
pub const IDLE_AFTER_NS: i128 = 60_000_000_000;

/// The configuration as the IPC layer hands it over, before normalisation.
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
    /// `NewRateLimiter`/`UpdateConfig` normalisation.
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

/// The values the limiter actually runs with.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Normalized {
    pub enabled: bool,
    pub rate: f64,
    pub burst: i64,
    pub ipv4_prefix: u8,
    pub ipv6_prefix: u8,
}

/// A snapshot for diagnostics and tests: the normalised config plus the table sizes.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Info {
    pub config: Normalized,
    pub buckets: u32,
    pub exempt_ips: u32,
    pub exempt_nets: u32,
}

/// `isIdle`'s shape: full and untouched for over a minute.
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

    /// `clientBucket.allow`: refill since the last call, clamp to burst, consume one token.
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

    /// `bucketKey`: mask by family, so a whole prefix shares one bucket.
    fn bucket_key(&self, address: &Addr) -> Addr {
        match address {
            Addr::V4(_) => address.masked(self.config.ipv4_prefix),
            Addr::V6(_) => address.masked(self.config.ipv6_prefix),
        }
    }

    /// `parseExemptions`: trim, then CIDR when there is a `/`, else a literal address.
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

/// One service generation's limiter. `UpdateConfig` mutates it in place, like the Go struct.
pub struct RateLimiter {
    state: RwLock<State>,
}

impl RateLimiter {
    /// `NewRateLimiter`: normalise, parse the exemptions, start with no buckets.
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

    /// `UpdateConfig`: replace the config and exemptions, adjust every live bucket.
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

    /// `IsEnabled`.
    pub fn enabled(&self) -> bool {
        self.read().config.enabled
    }

    /// `IsExempt`; a missing address (`nil` in Go) counts as exempt.
    pub fn is_exempt(&self, address: Option<&Addr>) -> bool {
        let Some(address) = address else {
            return true;
        };
        self.read().is_exempt(address)
    }

    /// `Allow`.
    ///
    /// `max_buckets` is the Go field of the same name: it exists as a knob in Go's tests, so it is
    /// passed per call instead of being duplicated in the kernel. `0` means "keep at most one
    /// bucket", which is what the Go loop does (it evicts the oldest, then inserts).
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
                // The idle pass is dead code on both sides (see the module docs), but it is part of
                // the decision order: idle buckets first, then the least recently written one.
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

    /// `cleanupIdleBuckets` — the Go janitor's once-a-minute call.
    pub fn cleanup_idle(&self, now_ns: i64) {
        let now_ns = i128::from(now_ns);
        self.write()
            .buckets
            .retain(|_, bucket| !bucket.is_idle(now_ns));
    }

    /// Sizes and normalised values, for diagnostics and tests.
    pub fn info(&self) -> Info {
        let state = self.read();
        Info {
            config: state.config,
            buckets: state.buckets.len() as u32,
            exempt_ips: state.exempt_ips.len() as u32,
            exempt_nets: state.exempt_nets.len() as u32,
        }
    }

    /// Current bucket count.
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

/// Prefix normalisation shared by both families.
fn prefix_or_default(value: i64, maximum: i64) -> u8 {
    if value <= 0 || value > maximum {
        maximum as u8
    } else {
        value as u8
    }
}

#[cfg(test)]
mod tests;
